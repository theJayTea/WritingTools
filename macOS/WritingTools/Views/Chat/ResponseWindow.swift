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
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        
        for type in [.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType] {
            self.standardWindowButton(type)?.isHidden = true
        }
        
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
