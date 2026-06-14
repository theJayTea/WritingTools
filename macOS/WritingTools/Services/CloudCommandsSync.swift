//
//  CloudCommandsSync.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 15.08.25.
//

import Foundation

private let logger = AppLogger.logger("CloudCommandsSync")

extension Notification.Name {
  static let iCloudCommandSyncQuotaExceeded = Notification.Name("iCloudCommandSyncQuotaExceeded")
}

enum CloudCommandsSyncUserInfoKey {
  static let payloadBytes = "payloadBytes"
  static let totalBytes = "totalBytes"
  static let reason = "reason"
}

@MainActor
final class CloudCommandsSync {
  enum SyncHealth: Equatable {
    case idle
    case synced
    case quotaLimited(reason: String, payloadBytes: Int?, totalBytes: Int?)
  }

  static let shared = CloudCommandsSync()

  private let store = NSUbiquitousKeyValueStore.default

  // Keys for the "full command list" (edited built-ins + custom)
  private let dataKey = "icloud.commandManager.commands.v1.data"
  private let mtimeKey = "icloud.commandManager.commands.v1.mtime"
  private let deletedIdsKey = "icloud.commandManager.commands.v1.deleted_ids"
  private let localMTimeKey = "local.commandManager.commands.v1.mtime"
  private let localDeletedIdsKey = "local.commandManager.commands.v1.deleted_ids"
  private let localDeletedTimestampByIdKey = "local.commandManager.commands.v1.deleted_ts_by_id"
  private let localKnownIdsKey = "local.commandManager.commands.v1.known_ids"

  private var started = false
  /// Monotonic counter incremented each time a cloud pull applies changes.
  /// Push is suppressed when the counter changes between scheduling and execution.
  private var cloudApplyGeneration: UInt64 = 0
  private var syncInProgress = false
  private var pendingSync = false
  /// Brief suppression flag set while applying remote changes to prevent
  /// the `CommandsChanged` notification from triggering a redundant push.
  private var suppressPush = false
  private var lastQuotaWarningDate: Date?
  private var deletedCommandIds: Set<UUID> = []
  private var deletedCommandTimestamps: [UUID: Date] = [:]
  private var knownLocalCommandIds: Set<UUID> = []
  private(set) var syncHealth: SyncHealth = .idle

  private var commandsChangedObserver: NSObjectProtocol?
  private var kvsObserver: NSObjectProtocol?
  private var pushDebounceTask: Task<Void, Never>?
  private let pushDebounceDelay: Duration = .milliseconds(300)
  private let kvsValueQuotaBytes = 1_000_000
  /// `NSUbiquitousKeyValueStore` allows at most 1024 keys total per store.
  private let kvsMaxKeyCount = 1024
  private let quotaWarningDebounceInterval: TimeInterval = 30
  private let maxDeletedTombstones = 512

  private init() {
    loadLocalSyncState()
    // Started explicitly by AppDelegate based on user preference.
  }

  func setEnabled(_ enabled: Bool) {
    if enabled {
      start()
    } else {
      stop()
    }
  }

  func start() {
    guard !started else { return }
    started = true
    bootstrapKnownLocalIdsIfNeeded()

    // Initial pull from iCloud if remote is newer
    schedulePull()

    // Listen for your app's commands change notification
    commandsChangedObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name("CommandsChanged"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.schedulePush()
      }
    }

    // Listen for iCloud server changes
    kvsObserver = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store,
      queue: .main
    ) { [weak self] note in
      // Hop to MainActor before calling a MainActor-isolated method
      Task { @MainActor in
        self?.handleICloudChange(note)
      }
    }

    _ = store.synchronize()
  }

  func stop() {
    guard started else { return }
    started = false

    if let commandsChangedObserver {
      NotificationCenter.default.removeObserver(commandsChangedObserver)
      self.commandsChangedObserver = nil
    }
    if let kvsObserver {
      NotificationCenter.default.removeObserver(kvsObserver)
      self.kvsObserver = nil
    }
    pushDebounceTask?.cancel()
    pushDebounceTask = nil
    syncInProgress = false
    pendingSync = false
    syncHealth = .idle
  }

  /// Cancel any pending debounce, push local commands immediately, and
  /// call `synchronize()` to flush the KVS write to the daemon before
  /// the process exits. Call from `applicationWillTerminate`.
  func flushAndSynchronize() {
    guard started else { return }
    pushDebounceTask?.cancel()
    pushDebounceTask = nil
    pushLocalToICloud()
    _ = store.synchronize()
  }

  // MARK: - Push local -> iCloud

  private func schedulePush() {
    // Skip pushes triggered by applying remote changes
    guard !suppressPush else { return }

    let generationAtSchedule = cloudApplyGeneration

    pushDebounceTask?.cancel()
    pushDebounceTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: self.pushDebounceDelay)
      guard !Task.isCancelled else { return }
      // Skip the push if a cloud pull happened since this push was scheduled
      guard self.cloudApplyGeneration == generationAtSchedule else { return }
      self.pushLocalToICloud()
    }
  }

  private func pushLocalToICloud() {

    let commands = AppState.shared.commandManager.commands
    let now = Date()
    let currentIds = Set(commands.map(\.id))
    let removedIds = knownLocalCommandIds.subtracting(currentIds)

    // Persist local deletion intent so it survives restarts/offline periods.
    deletedCommandIds.formUnion(removedIds)
    for id in removedIds where deletedCommandTimestamps[id] == nil {
      deletedCommandTimestamps[id] = now
    }
    // Undelete semantics: if a command exists locally, it should not remain tombstoned.
    deletedCommandIds.subtract(currentIds)
    for id in currentIds {
      deletedCommandTimestamps[id] = nil
    }
    _ = compactDeletedTombstones(maxCount: maxDeletedTombstones, maxDeletedIdsBytes: nil)
    knownLocalCommandIds = currentIds
    persistLocalSyncState()

    do {
      let data = try JSONEncoder().encode(commands)
      let dataBytes = estimatedKVSValueSize(of: data)
      guard dataBytes <= kvsValueQuotaBytes else {
        logger.error("CloudCommandsSync: push skipped because encoded command payload exceeds iCloud KVS value quota (\(dataBytes) bytes)")
        postQuotaWarningIfNeeded(
          payloadBytes: dataBytes,
          totalBytes: nil,
          reason: "preflight_payload_too_large"
        )
        return
      }

      var deletedIdsPayload = encodeUUIDSet(deletedCommandIds)
      var preflight = preflightBudget(
        commandData: data,
        deletedIdsPayload: deletedIdsPayload,
        mtime: now
      )

      if !preflight.isWithinQuota {
        let deletedIdsBudget =
          max(0, kvsValueQuotaBytes - preflight.nonManagedBytes - preflight.commandBytes - preflight.mtimeBytes)
        if compactDeletedTombstones(maxCount: maxDeletedTombstones, maxDeletedIdsBytes: deletedIdsBudget) {
          deletedIdsPayload = encodeUUIDSet(deletedCommandIds)
          preflight = preflightBudget(
            commandData: data,
            deletedIdsPayload: deletedIdsPayload,
            mtime: now
          )
          persistLocalSyncState()
        }
      }

      guard preflight.isWithinQuota else {
        logger.error(
          "CloudCommandsSync: push skipped because estimated iCloud KVS total (\(preflight.totalBytes) bytes) exceeds quota"
        )
        postQuotaWarningIfNeeded(
          payloadBytes: preflight.commandBytes,
          totalBytes: preflight.totalBytes,
          reason: "preflight_total_store_too_large"
        )
        return
      }

      store.set(data, forKey: dataKey)
      if deletedIdsPayload.isEmpty {
        store.removeObject(forKey: deletedIdsKey)
      } else {
        store.set(deletedIdsPayload, forKey: deletedIdsKey)
      }
      store.set(now, forKey: mtimeKey)

      UserDefaults.standard.set(now, forKey: localMTimeKey)
      syncHealth = .synced
    } catch {
      logger.error("CloudCommandsSync: encode error: \(error.localizedDescription)")
    }
  }

  // MARK: - Pull iCloud -> local (if newer)

  private func schedulePull() {
    if syncInProgress {
      pendingSync = true
      return
    }

    syncInProgress = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        self.syncInProgress = false
        if self.pendingSync {
          self.pendingSync = false
          self.schedulePull()
        }
      }
      await self.pullFromICloudIfNewer()
    }
  }

  private func pullFromICloudIfNewer() async {
    // An in-flight pull Task may have been scheduled before `stop()` ran.
    // Bail out so we never mutate command state after sync was disabled.
    guard started else { return }

    guard let remoteMTime = store.object(forKey: mtimeKey) as? Date else {
      return
    }
    let localMTime =
      UserDefaults.standard.object(forKey: localMTimeKey) as? Date

    guard localMTime.map({ remoteMTime > $0 }) ?? true else {
      return
    }

    do {
      let remoteCommands: [CommandModel]
      if let data = store.data(forKey: dataKey) {
        remoteCommands = try JSONDecoder().decode([CommandModel].self, from: data)
      } else {
        remoteCommands = []
      }
      let remoteDeletedCommandIds = decodeUUIDSet(
        from: store.array(forKey: deletedIdsKey) as? [String]
      )
      for id in remoteDeletedCommandIds where deletedCommandTimestamps[id] == nil {
        deletedCommandTimestamps[id] = remoteMTime
      }

      // Cancel any in-flight push and increment the generation counter so
      // any push scheduled after the debounce period also gets skipped.
      pushDebounceTask?.cancel()
      pushDebounceTask = nil
      cloudApplyGeneration &+= 1

      // Per-command merge: instead of replacing the entire local list,
      // merge by command ID. Remote versions win for shared commands,
      // local-only commands are preserved, and remote-only commands are added.
      let localCommands = AppState.shared.commandManager.commands
      var effectiveTombstones = deletedCommandIds.union(remoteDeletedCommandIds)
      var mergedCommands = Self.mergeCommands(local: localCommands, remote: remoteCommands)
      mergedCommands.removeAll { effectiveTombstones.contains($0.id) }
      // If a command currently exists after merge, it is no longer deleted.
      effectiveTombstones.subtract(mergedCommands.map(\.id))

      // C2: Determine whether the reconciled result diverges from what iCloud
      // currently holds. Divergence happens when a local-only command survived
      // the merge, a local edit won a per-command timestamp race, or a remote
      // command was dropped by a local tombstone. In those cases we MUST push the
      // reconciled state back; otherwise the two devices stay permanently out of
      // sync until the user happens to make another edit.
      let remoteSnapshot = Dictionary(
        remoteCommands.map { ($0.id, $0.updatedAt) },
        uniquingKeysWith: { first, _ in first }
      )
      let mergedSnapshot = Dictionary(
        mergedCommands.map { ($0.id, $0.updatedAt) },
        uniquingKeysWith: { first, _ in first }
      )
      let mergedDivergesFromRemote = remoteSnapshot != mergedSnapshot

      // Suppress pushes while applying remote changes. The `replaceAllCommands`
      // call fires a `CommandsChanged` notification which would otherwise
      // schedule a redundant push-back of the data we just received. We re-enable
      // pushing afterward and, if the merge diverged from remote, schedule one
      // deliberate deferred push (see below) instead of relying on a future edit.
      do {
        suppressPush = true
        defer { suppressPush = false }
        AppState.shared.commandManager.replaceAllCommands(with: mergedCommands)
      }

      deletedCommandIds = effectiveTombstones
      deletedCommandTimestamps = deletedCommandTimestamps.filter { effectiveTombstones.contains($0.key) }
      _ = compactDeletedTombstones(maxCount: maxDeletedTombstones, maxDeletedIdsBytes: nil)
      knownLocalCommandIds = Set(mergedCommands.map(\.id))

      // Keep CommandManager's built-in deletion record in step with the merged
      // tombstone set, so a built-in deleted on another device stays deleted
      // here even across a future defaults re-initialization.
      AppState.shared.commandManager.reconcileDeletedBuiltInIds(withTombstones: effectiveTombstones)
      persistLocalSyncState()
      UserDefaults.standard.set(remoteMTime, forKey: localMTimeKey)
      syncHealth = .synced

      // C2: propagate a reconciled-but-divergent merge back to iCloud via the
      // normal debounced push. `suppressPush` is already false here (its `defer`
      // ran when the apply block above exited), and `schedulePush` captures the
      // current `cloudApplyGeneration`, so the push is skipped automatically if
      // another pull supersedes it before the debounce fires. Once both sides
      // hold identical data, the other device's next merge converges and does not
      // push back — so this cannot loop.
      if mergedDivergesFromRemote {
        logger.info("CloudCommandsSync: merged state diverges from remote; scheduling deferred push-back")
        schedulePush()
      }
    } catch {
      logger.error("CloudCommandsSync: decode error: \(error.localizedDescription)")
    }
  }

  /// Merges local and remote command lists by command ID.
  ///
  /// Per-command timestamp rule (protects offline local edits from being clobbered):
  /// - Commands present in BOTH: keep whichever side has the later `updatedAt`.
  ///   On a tie (equal timestamps, including the `.distantPast` default used by
  ///   built-ins/migration), prefer the REMOTE version. This is the existing
  ///   convention and avoids needless local churn when nothing meaningfully changed.
  ///   The store-level `remoteMTime > localMTime` gate still decides *whether* a pull
  ///   happens at all; this rule decides which version wins for each shared command so
  ///   a command edited locally more recently than its remote counterpart survives.
  /// - Commands only in remote: add them (new from another device).
  /// - Commands only in local: keep them (created locally, not yet pushed).
  ///
  /// Ordering follows the remote list (for shared and remote-only commands), with
  /// local-only commands appended at the end.
  nonisolated static func mergeCommands(local: [CommandModel], remote: [CommandModel]) -> [CommandModel] {
    let remoteIds = Set(remote.map(\.id))
    let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // Start from the remote list, preserving remote ordering. For each shared
    // command, swap in the local version only when local is strictly newer.
    var merged = remote.map { remoteCommand -> CommandModel in
      guard let localCommand = localById[remoteCommand.id] else { return remoteCommand }
      // Local wins only when strictly newer; ties go to remote.
      return localCommand.updatedAt > remoteCommand.updatedAt ? localCommand : remoteCommand
    }

    // Append any local-only commands (not present in remote) at the end
    for command in local where !remoteIds.contains(command.id) {
      merged.append(command)
    }

    return merged
  }

  private func handleICloudChange(_ note: Notification) {
    guard
      let userInfo = note.userInfo,
      let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    else { return }

    if Self.isQuotaViolationReason(reason) {
      logger.error("CloudCommandsSync: received iCloud KVS quota violation change notification")
      postQuotaWarningIfNeeded(
        payloadBytes: nil,
        totalBytes: nil,
        reason: "quota_violation_notification"
      )
      return
    }

    if Self.isAccountChangeReason(reason) {
      logger.info("CloudCommandsSync: received iCloud account-change notification; resetting local sync markers and reconciling")
      resetLocalSyncMarkersForAccountChange()
      schedulePull()
      return
    }

    guard Self.isServerDrivenPullReason(reason)
    else {
      return
    }

    let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
    if Self.hasRelevantChangedKeys(changedKeys, dataKey: dataKey, mtimeKey: mtimeKey, deletedIdsKey: deletedIdsKey) {
      schedulePull()
    }
  }

  nonisolated static func isQuotaViolationReason(_ reason: Int) -> Bool {
    reason == NSUbiquitousKeyValueStoreQuotaViolationChange
  }

  nonisolated static func isAccountChangeReason(_ reason: Int) -> Bool {
    reason == NSUbiquitousKeyValueStoreAccountChange
  }

  nonisolated static func isServerDrivenPullReason(_ reason: Int) -> Bool {
    reason == NSUbiquitousKeyValueStoreServerChange
      || reason == NSUbiquitousKeyValueStoreInitialSyncChange
  }

  nonisolated static func hasRelevantChangedKeys(
    _ changedKeys: [String]?,
    dataKey: String,
    mtimeKey: String,
    deletedIdsKey: String
  ) -> Bool {
    guard let changedKeys else { return false }
    return changedKeys.contains { key in
      key == dataKey || key == mtimeKey || key == deletedIdsKey
    }
  }

  private func resetLocalSyncMarkersForAccountChange() {
    // Clear stale reconciliation state so the next pull is computed against the new account.
    pushDebounceTask?.cancel()
    pushDebounceTask = nil
    cloudApplyGeneration &+= 1

    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: localMTimeKey)

    deletedCommandIds.removeAll()
    deletedCommandTimestamps.removeAll()
    knownLocalCommandIds = Set(AppState.shared.commandManager.commands.map(\.id))
    persistLocalSyncState()

    logger.info("CloudCommandsSync: local sync markers reset after account change")
  }

  private func bootstrapKnownLocalIdsIfNeeded() {
    guard knownLocalCommandIds.isEmpty else { return }
    knownLocalCommandIds = Set(AppState.shared.commandManager.commands.map(\.id))
    persistLocalSyncState()
  }

  private func loadLocalSyncState() {
    let defaults = UserDefaults.standard
    deletedCommandIds = decodeUUIDSet(from: defaults.stringArray(forKey: localDeletedIdsKey))
    deletedCommandTimestamps = decodeDeletedCommandTimestamps(
      from: defaults.dictionary(forKey: localDeletedTimestampByIdKey)
    )
    // Keep timestamp map aligned with tombstone set, and seed missing entries.
    deletedCommandTimestamps = deletedCommandTimestamps.filter { deletedCommandIds.contains($0.key) }
    for id in deletedCommandIds where deletedCommandTimestamps[id] == nil {
      deletedCommandTimestamps[id] = .distantPast
    }
    knownLocalCommandIds = decodeUUIDSet(from: defaults.stringArray(forKey: localKnownIdsKey))
  }

  private func persistLocalSyncState() {
    let defaults = UserDefaults.standard
    defaults.set(encodeUUIDSet(deletedCommandIds), forKey: localDeletedIdsKey)
    defaults.set(
      encodeDeletedCommandTimestamps(deletedCommandTimestamps),
      forKey: localDeletedTimestampByIdKey
    )
    defaults.set(encodeUUIDSet(knownLocalCommandIds), forKey: localKnownIdsKey)
  }

  private func encodeUUIDSet(_ ids: Set<UUID>) -> [String] {
    ids.map(\.uuidString).sorted()
  }

  private func decodeUUIDSet(from rawValues: [String]?) -> Set<UUID> {
    Set((rawValues ?? []).compactMap(UUID.init(uuidString:)))
  }

  private func encodeDeletedCommandTimestamps(_ timestamps: [UUID: Date]) -> [String: TimeInterval] {
    var encoded: [String: TimeInterval] = [:]
    for (id, date) in timestamps {
      encoded[id.uuidString] = date.timeIntervalSince1970
    }
    return encoded
  }

  private func decodeDeletedCommandTimestamps(from rawValues: [String: Any]?) -> [UUID: Date] {
    var decoded: [UUID: Date] = [:]
    for (rawId, rawTimestamp) in rawValues ?? [:] {
      guard let id = UUID(uuidString: rawId) else { continue }
      if let timestampNumber = rawTimestamp as? NSNumber {
        decoded[id] = Date(timeIntervalSince1970: timestampNumber.doubleValue)
      }
    }
    return decoded
  }

  private func compactDeletedTombstones(maxCount: Int, maxDeletedIdsBytes: Int?) -> Bool {
    guard !deletedCommandIds.isEmpty else { return false }

    let sortedIds = deletedCommandIds.sorted { lhs, rhs in
      let lhsDate = deletedCommandTimestamps[lhs] ?? .distantPast
      let rhsDate = deletedCommandTimestamps[rhs] ?? .distantPast
      if lhsDate == rhsDate {
        return lhs.uuidString < rhs.uuidString
      }
      return lhsDate > rhsDate
    }

    var keptIds: [UUID] = []
    let cappedCount = max(0, maxCount)

    // When a byte budget is specified, estimate the per-UUID overhead once
    // (all UUIDs are 36 characters and produce identical plist overhead)
    // rather than re-serializing the growing array on every iteration.
    let perUUIDByteEstimate: Int? = {
        guard maxDeletedIdsBytes != nil else { return nil }
      // Measure the marginal cost of a single UUID in a plist array.
      let oneItem = estimatedKVSValueSize(of: [UUID().uuidString])
      let twoItems = estimatedKVSValueSize(of: [UUID().uuidString, UUID().uuidString])
      let marginal = twoItems - oneItem
      let baseOverhead = oneItem - marginal
      // We'll check: baseOverhead + count * marginal <= maxDeletedIdsBytes
      _ = baseOverhead
      return marginal > 0 ? marginal : nil
    }()

    if let maxDeletedIdsBytes, let perUUID = perUUIDByteEstimate {
      // Fast path: estimate byte cost arithmetically
      let oneItem = estimatedKVSValueSize(of: [UUID().uuidString])
      let baseOverhead = oneItem - perUUID
      let maxByCount = maxDeletedIdsBytes >= baseOverhead
        ? (maxDeletedIdsBytes - baseOverhead) / perUUID
        : 0
      let effectiveCap = min(cappedCount, maxByCount)
      keptIds = Array(sortedIds.prefix(effectiveCap))
    } else {
      keptIds = Array(sortedIds.prefix(cappedCount))
    }

    let newSet = Set(keptIds)
    guard newSet != deletedCommandIds else { return false }

    let removedCount = deletedCommandIds.count - newSet.count
    deletedCommandIds = newSet
    deletedCommandTimestamps = deletedCommandTimestamps.filter { newSet.contains($0.key) }
    logger.warning("CloudCommandsSync: compacted \(removedCount) deleted-command tombstones")
    return true
  }

  private struct KVSPreflightResult {
    let commandBytes: Int
    let deletedIdsBytes: Int
    let mtimeBytes: Int
    let nonManagedBytes: Int
    let totalBytes: Int
    let keyCount: Int
    let isWithinQuota: Bool
  }

  private func preflightBudget(
    commandData: Data,
    deletedIdsPayload: [String],
    mtime: Date
  ) -> KVSPreflightResult {
    let managedKeys: Set<String> = [dataKey, deletedIdsKey, mtimeKey]
    var nonManagedKeyCount = 0
    let nonManagedBytes = store.dictionaryRepresentation.reduce(into: 0) { partialResult, entry in
      guard !managedKeys.contains(entry.key) else { return }
      nonManagedKeyCount += 1
      partialResult += estimatedKVSValueSize(of: entry.value)
    }

    let commandBytes = estimatedKVSValueSize(of: commandData)
    let deletedIdsBytes = deletedIdsPayload.isEmpty ? 0 : estimatedKVSValueSize(of: deletedIdsPayload)
    let mtimeBytes = estimatedKVSValueSize(of: mtime)
    let totalBytes = nonManagedBytes + commandBytes + deletedIdsBytes + mtimeBytes

    // Managed keys this push actually writes: dataKey and mtimeKey are always
    // written; deletedIdsKey is written only when the payload is non-empty
    // (otherwise the existing object is removed).
    let managedKeyCount = 2 + (deletedIdsPayload.isEmpty ? 0 : 1)
    let keyCount = nonManagedKeyCount + managedKeyCount

    let isWithinPerValueLimit =
      commandBytes <= kvsValueQuotaBytes
      && deletedIdsBytes <= kvsValueQuotaBytes
      && mtimeBytes <= kvsValueQuotaBytes

    return KVSPreflightResult(
      commandBytes: commandBytes,
      deletedIdsBytes: deletedIdsBytes,
      mtimeBytes: mtimeBytes,
      nonManagedBytes: nonManagedBytes,
      totalBytes: totalBytes,
      keyCount: keyCount,
      // KVS enforces both a byte budget and a 1024-key limit; exceeding either
      // is treated as a quota failure.
      isWithinQuota: isWithinPerValueLimit
        && totalBytes <= kvsValueQuotaBytes
        && keyCount <= kvsMaxKeyCount
    )
  }

  private func estimatedKVSValueSize(of value: Any) -> Int {
    guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
      return 0
    }
    guard let data = try? PropertyListSerialization.data(
      fromPropertyList: value,
      format: .binary,
      options: 0
    ) else {
      return 0
    }
    return data.count
  }

  private func postQuotaWarningIfNeeded(payloadBytes: Int?, totalBytes: Int?, reason: String) {
    let now = Date()
    if let lastQuotaWarningDate,
       now.timeIntervalSince(lastQuotaWarningDate) < quotaWarningDebounceInterval {
      return
    }
    lastQuotaWarningDate = now
    syncHealth = .quotaLimited(reason: reason, payloadBytes: payloadBytes, totalBytes: totalBytes)

    var userInfo: [String: Any] = [
      CloudCommandsSyncUserInfoKey.reason: reason
    ]
    if let payloadBytes {
      userInfo[CloudCommandsSyncUserInfoKey.payloadBytes] = payloadBytes
    }
    if let totalBytes {
      userInfo[CloudCommandsSyncUserInfoKey.totalBytes] = totalBytes
    }

    NotificationCenter.default.post(
      name: .iCloudCommandSyncQuotaExceeded,
      object: nil,
      userInfo: userInfo
    )
  }
}
