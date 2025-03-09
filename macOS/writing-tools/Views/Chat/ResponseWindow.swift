import SwiftUI

class ResponseWindow: NSWindow {
    init(title: String, content: String, selectedText: String, option: WritingOption? = nil) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = title
        self.minSize = NSSize(width: 400, height: 300)
        self.isReleasedWhenClosed = false
        self.titlebarAppearsTransparent = true
        
        let toolbarIdentifier = NSToolbar.Identifier("ResponseWindowToolbar")
        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
        
        let contentView = ResponseView(
            content: content,
            selectedText: selectedText,
            option: option
        )
        
        self.contentView = NSHostingView(rootView: contentView)
        self.center()
        self.setFrameAutosaveName("ResponseWindow")
    }
    
    override func close() {
        // Notify WindowManager to clean up
        WindowManager.shared.removeResponseWindow(self)
        super.close()
    }
}
