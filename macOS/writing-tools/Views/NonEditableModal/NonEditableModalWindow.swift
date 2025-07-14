import SwiftUI

class NonEditableModalWindow: NSWindow {
    init(transformedText: String, originalText: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        
        let contentView = NonEditableModalView(
            transformedText: transformedText,
            originalText: originalText,
            closeAction: { [weak self] in
                self?.close()
            }
        )
        
        self.contentView = NSHostingView(rootView: contentView)
        self.positionNearCursor()
    }
    
    private func positionNearCursor() {
        guard let screen = NSScreen.main else { return }
        
        // Get cursor position
        let mouseLocation = NSEvent.mouseLocation
        
        // Calculate position (offset from cursor)
        var x = mouseLocation.x + 20
        var y = mouseLocation.y - 20
        
        // Adjust if window would go off screen
        let screenFrame = screen.visibleFrame
        if x + self.frame.width > screenFrame.maxX {
            x = screenFrame.maxX - self.frame.width
        }
        if y - self.frame.height < screenFrame.minY {
            y = mouseLocation.y + self.frame.height + 20
        }
        
        // Ensure window stays on screen
        x = max(screenFrame.minX, x)
        y = max(screenFrame.minY + self.frame.height, y)
        
        self.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }
    
    override func close() {
        // Notify WindowManager to clean up
        WindowManager.shared.removeNonEditableModal(self)
        super.close()
    }
}
