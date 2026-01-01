//
//  ClipboardWait.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 08.08.25.
//

import AppKit

private let logger = AppLogger.logger("ClipboardWait")

func waitForPasteboardUpdate(
  _ pb: NSPasteboard,
  initialChangeCount: Int,
  timeout: TimeInterval = 0.6
) async {
  let start = Date()
  while pb.changeCount == initialChangeCount && Date().timeIntervalSince(start) <
    timeout
  {
      do {
          try await Task.sleep(for: .milliseconds(20))
      } catch {
          logger.debug("Task sleep interrupted: \(error.localizedDescription)")
      } // 20 ms
  }
}
