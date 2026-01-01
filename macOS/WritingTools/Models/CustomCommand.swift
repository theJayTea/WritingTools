import Foundation
import Observation

private let logger = AppLogger.logger("CustomCommandsManager")

struct CustomCommand: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var prompt: String
  var icon: String
  var useResponseWindow: Bool

  init(
    id: UUID = UUID(),
    name: String,
    prompt: String,
    icon: String,
    useResponseWindow: Bool = false
  ) {
    self.id = id
    self.name = name
    self.prompt = prompt
    self.icon = icon
    self.useResponseWindow = useResponseWindow
  }
}

@Observable
final class CustomCommandsManager {
  private(set) var commands: [CustomCommand] = []

  private let saveKey = "custom_commands"

  // iCloud KVS
  private let iCloudStore = NSUbiquitousKeyValueStore.default
  private let iCloudDataKey = "icloud.custom_commands.v1.data"
  private let iCloudMTimeKey = "icloud.custom_commands.v1.mtime"
  private let localMTimeDefaultsKey = "custom_commands_mtime.v1"

  // Prevents push loops when applying remote changes
  private var isApplyingCloudChange = false

  private var kvsObserver: NSObjectProtocol?

  init() {
    // Load local first
    loadLocalCommands()

    // Start iCloud sync
    // Pull from iCloud if newer than local
    pullFromICloudIfNewer()

    // Observe KVS remote changes
    kvsObserver = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: iCloudStore,
      queue: .main
    ) { [weak self] note in
      self?.handleICloudChange(note)
    }
  }

  deinit {
    if let kvsObserver {
      NotificationCenter.default.removeObserver(kvsObserver)
    }
  }

  // MARK: - Public API

  func addCommand(_ command: CustomCommand) {
    commands.append(command)
    saveCommands()
  }

  func updateCommand(_ command: CustomCommand) {
    if let index = commands.firstIndex(where: { $0.id == command.id }) {
      commands[index] = command
      saveCommands()
    }
  }

  func deleteCommand(_ command: CustomCommand) {
    commands.removeAll { $0.id == command.id }
    saveCommands()
  }

  // Replace all custom commands at once (kept for your existing usage)
  func replaceCommands(with newCommands: [CustomCommand]) {
    commands = newCommands
    saveCommands()
  }

  // MARK: - Local persistence

  private func loadLocalCommands() {
    if
      let data = UserDefaults.standard.data(forKey: saveKey),
      let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data)
    {
      commands = decoded
    }
  }

  private func saveLocalCommands() {
    if let encoded = try? JSONEncoder().encode(commands) {
      UserDefaults.standard.set(encoded, forKey: saveKey)
    }
  }

  // MARK: - iCloud sync

  // Push local -> iCloud, with modified time
  private func pushToICloud() {
    guard !isApplyingCloudChange else { return }

    do {
      let data = try JSONEncoder().encode(commands)
      let now = Date()

      iCloudStore.set(data, forKey: iCloudDataKey)
      iCloudStore.set(now, forKey: iCloudMTimeKey)

      UserDefaults.standard.set(now, forKey: localMTimeDefaultsKey)
    } catch {
      logger.error("CustomCommandsManager: Failed to encode for iCloud: \(error.localizedDescription)")
    }
  }

  // Pull iCloud -> local if iCloud is newer
  private func pullFromICloudIfNewer() {
    guard let remoteMTime = iCloudStore.object(forKey: iCloudMTimeKey) as? Date
    else { return }

    let localMTime =
      UserDefaults.standard.object(forKey: localMTimeDefaultsKey) as? Date

    guard localMTime == nil || remoteMTime > localMTime! else {
      return
    }

    guard let data = iCloudStore.data(forKey: iCloudDataKey) else { return }

    do {
      let remoteCommands =
        try JSONDecoder().decode([CustomCommand].self, from: data)

      isApplyingCloudChange = true
      self.commands = remoteCommands
      saveLocalCommands()

      // Update local mtime after applying
      UserDefaults.standard.set(remoteMTime, forKey: localMTimeDefaultsKey)
      isApplyingCloudChange = false

    } catch {
      logger.error("CustomCommandsManager: Failed to decode from iCloud: \(error.localizedDescription)")
    }
  }

  private func handleICloudChange(_ note: Notification) {
    guard
      let userInfo = note.userInfo,
      let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey]
        as? Int
    else { return }

    guard reason == NSUbiquitousKeyValueStoreServerChange
      || reason == NSUbiquitousKeyValueStoreInitialSyncChange
    else {
      return
    }

    if
      let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey]
        as? [String],
      changedKeys.contains(where: { $0 == iCloudDataKey || $0 == iCloudMTimeKey })
    {
      pullFromICloudIfNewer()
    }
  }

  // Save both locally and to iCloud
  private func saveCommands() {
    saveLocalCommands()

    // Update local modified time first
    let now = Date()
    UserDefaults.standard.set(now, forKey: localMTimeDefaultsKey)

    // Push to iCloud unless we’re applying a remote change
    pushToICloud()
  }
}
