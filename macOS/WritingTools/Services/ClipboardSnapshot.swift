//
//  ClipboardSnapshot.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 17.11.25.
//

import AppKit

/// A comprehensive snapshot of the clipboard state that captures all items and all types
struct ClipboardSnapshot {
    /// All pasteboard items with their data
    private let items: [[NSPasteboard.PasteboardType: Data]]
    
    /// The change count at the time of snapshot
    let changeCount: Int
    
    /// Creates a snapshot of the current clipboard state
    init() {
        let pb = NSPasteboard.general
        self.changeCount = pb.changeCount
        
        var capturedItems: [[NSPasteboard.PasteboardType: Data]] = []
        
        // Capture all items on the pasteboard
        if let pasteboardItems = pb.pasteboardItems {
            for item in pasteboardItems {
                var itemData: [NSPasteboard.PasteboardType: Data] = [:]
                
                // Get all types available for this item
                for type in item.types {
                    // Try to get data for each type
                    if let data = item.data(forType: type) {
                        itemData[type] = data
                    }
                }
                
                if !itemData.isEmpty {
                    capturedItems.append(itemData)
                }
            }
        }
        
        self.items = capturedItems
        
        NSLog("ClipboardSnapshot: Captured \(capturedItems.count) items with total types: \(capturedItems.flatMap { $0.keys }.count)")
    }
    
    /// Restores this snapshot to the clipboard
    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        guard !items.isEmpty else {
            NSLog("ClipboardSnapshot: No items to restore")
            return
        }
        
        // Prepare pasteboard items
        var pasteboardItems: [NSPasteboardItem] = []
        
        for itemData in items {
            let pasteboardItem = NSPasteboardItem()
            
            // Set data for each type
            for (type, data) in itemData {
                pasteboardItem.setData(data, forType: type)
            }
            
            pasteboardItems.append(pasteboardItem)
        }
        
        // Write all items to the pasteboard
        let success = pb.writeObjects(pasteboardItems)
        
        if success {
            NSLog("ClipboardSnapshot: Successfully restored \(pasteboardItems.count) items")
        } else {
            NSLog("ClipboardSnapshot: Failed to restore clipboard items")
        }
    }
    
    /// Returns true if this snapshot contains any data
    var isEmpty: Bool {
        return items.isEmpty
    }
    
    /// Returns the number of items in this snapshot
    var itemCount: Int {
        return items.count
    }
    
    /// Returns a debug description of the snapshot
    var debugDescription: String {
        var description = "ClipboardSnapshot: \(items.count) items\n"
        for (index, item) in items.enumerated() {
            description += "  Item \(index): \(item.keys.map { $0.rawValue }.joined(separator: ", "))\n"
        }
        return description
    }
}

extension NSPasteboard {
    /// Convenience method to create and return a snapshot
    func createSnapshot() -> ClipboardSnapshot {
        return ClipboardSnapshot()
    }
    
    /// Convenience method to restore a snapshot
    func restore(snapshot: ClipboardSnapshot) {
        snapshot.restore()
    }
}
