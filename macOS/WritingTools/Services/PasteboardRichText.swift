//
//  PasteboardRichText.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 08.08.25.
//

import AppKit

extension NSPasteboard {
  func readAttributedSelection() -> NSAttributedString? {
    // Prefer RTFD (common in Apple apps), then RTF, then HTML
    if let flatRtfd = data(forType: NSPasteboard.PasteboardType(
      "com.apple.flat-rtfd"
    )) {
      if let att = try? NSAttributedString(
        data: flatRtfd,
        options: [.documentType: NSAttributedString.DocumentType.rtfd],
        documentAttributes: nil
      ) {
        return att
      }
    }

    if let rtfd = data(forType: .rtfd) {
      if let att = try? NSAttributedString(
        data: rtfd,
        options: [.documentType: NSAttributedString.DocumentType.rtfd],
        documentAttributes: nil
      ) {
        return att
      }
    }

    if let rtf = data(forType: .rtf) {
      if let att = try? NSAttributedString(
        data: rtf,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      ) {
        return att
      }
    }

    if let html = data(forType: .html) {
      if let att = try? NSAttributedString(
        data: html,
        options: [.documentType: NSAttributedString.DocumentType.html],
        documentAttributes: nil
      ) {
        return att
      }
    }

    return nil
  }
}
