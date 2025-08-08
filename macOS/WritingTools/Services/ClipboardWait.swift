//
//  ClipboardWait.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 08.08.25.
//

import AppKit

func waitForPasteboardUpdate(
  _ pb: NSPasteboard,
  initialChangeCount: Int,
  timeout: TimeInterval = 0.6
) async {
  let start = Date()
  while pb.changeCount == initialChangeCount && Date().timeIntervalSince(start) <
    timeout
  {
    try? await Task.sleep(nanoseconds: 20_000_000) // 20 ms
  }
}
