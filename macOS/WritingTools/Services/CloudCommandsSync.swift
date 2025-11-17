//
//  CloudCommandsSync.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 15.08.25.
//

import Foundation
import Combine

@MainActor
final class CloudCommandsSync {
  static let shared = CloudCommandsSync()

  private let store = NSUbiquitousKeyValueStore.default

  // Keys for the "full command list" (edited built-ins + custom)
  private let dataKey = "icloud.commandManager.commands.v1.data"
  private let mtimeKey = "icloud.commandManager.commands.v1.mtime"
  private let localMTimeKey = "local.commandManager.commands.v1.mtime"

  private var started = false
  private var isApplyingCloudChange = false

  private var commandsChangedObserver: NSObjectProtocol?
  private var kvsObserver: NSObjectProtocol?
  private var objectWillChangeCancellable: AnyCancellable?

  private init() {
    // Start shortly after init to ensure AppState is ready
    DispatchQueue.main.async { [weak self] in
      Task { @MainActor in
        self?.start()
      }
    }
  }

  func start() {
    guard !started else { return }
    started = true

    store.synchronize()

    // Initial pull from iCloud if remote is newer
    pullFromICloudIfNewer()

    // Listen for your app's commands change notification
    commandsChangedObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name("CommandsChanged"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // Ensure we run on the MainActor
      Task { @MainActor in
        self?.pushLocalToICloud()
      }
    }

    // Also observe objectWillChange to catch reorders, etc.
    objectWillChangeCancellable =
      AppState.shared.commandManager.objectWillChange
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.pushLocalToICloud()
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
  }

  deinit {
    if let commandsChangedObserver {
      NotificationCenter.default.removeObserver(commandsChangedObserver)
    }
    if let kvsObserver {
      NotificationCenter.default.removeObserver(kvsObserver)
    }
    objectWillChangeCancellable?.cancel()
  }

  // MARK: - Push local -> iCloud

  private func pushLocalToICloud() {
    guard !isApplyingCloudChange else { return }

    let commands = AppState.shared.commandManager.commands

    do {
      let data = try JSONEncoder().encode(commands)
      let now = Date()

      store.set(data, forKey: dataKey)
      store.set(now, forKey: mtimeKey)
      store.synchronize()

      UserDefaults.standard.set(now, forKey: localMTimeKey)
    } catch {
      print("CloudCommandsSync: encode error: \(error)")
    }
  }

  // MARK: - Pull iCloud -> local (if newer)

  private func pullFromICloudIfNewer() {
    guard let remoteMTime = store.object(forKey: mtimeKey) as? Date else {
      return
    }
    let localMTime =
      UserDefaults.standard.object(forKey: localMTimeKey) as? Date

    guard localMTime == nil || remoteMTime > localMTime! else {
      return
    }

    guard let data = store.data(forKey: dataKey) else { return }

    do {
      let remoteCommands = try JSONDecoder().decode([CommandModel].self, from: data)

      isApplyingCloudChange = true
      AppState.shared.commandManager.replaceAllCommands(with: remoteCommands)
      UserDefaults.standard.set(remoteMTime, forKey: localMTimeKey)
      isApplyingCloudChange = false

      // Notify any listeners if necessary
      NotificationCenter.default.post(
        name: NSNotification.Name("CommandsChanged"),
        object: nil
      )
    } catch {
      print("CloudCommandsSync: decode error: \(error)")
    }
  }

  private func handleICloudChange(_ note: Notification) {
    guard
      let userInfo = note.userInfo,
      let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    else { return }

    guard reason == NSUbiquitousKeyValueStoreServerChange
      || reason == NSUbiquitousKeyValueStoreInitialSyncChange
    else {
      return
    }

    if
      let changedKeys =
        userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
      changedKeys.contains(where: { $0 == dataKey || $0 == mtimeKey })
    {
      pullFromICloudIfNewer()
    }
  }
}
