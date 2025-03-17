import SwiftUI

class FloatingIconWindow: NSWindow {
    private var trackingArea: NSTrackingArea?
    private let appState: AppState
    private let iconSize: CGFloat = 32
    
    init(appState: AppState) {
        self.appState = appState
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        
        configureWindow()
    }
    
    private func configureWindow() {
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        
        // Hide standard window buttons
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        
        let iconView = FloatingIconView {
            self.showPopup()
        }
        
        let hostingView = NSHostingView(rootView: iconView)
        contentView = hostingView
        
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        guard let contentView = contentView else { return }
        
        if let existing = trackingArea {
            contentView.removeTrackingArea(existing)
        }
        
        trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            contentView.addTrackingArea(trackingArea)
        }
    }
    
    private func showPopup() {
        // Cancel any ongoing processing
        appState.activeProvider.cancel()
        
        // Save the current app so we can return to it
        if let currentFrontmostApp = NSWorkspace.shared.frontmostApplication {
            appState.previousApplication = currentFrontmostApp
        }
        
        let generalPasteboard = NSPasteboard.general
        
        // Get initial pasteboard content
        let oldContents = generalPasteboard.string(forType: .string)
        
        // Prioritized image types (in order of preference)
        let supportedImageTypes = [
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.image")
        ]
        var foundImage: Data? = nil
        
        // Try to find the first available image in order of preference
        for type in supportedImageTypes {
            if let data = generalPasteboard.data(forType: type) {
                foundImage = data
                NSLog("Selected image type: \(type)")
                break // Take only the first matching format
            }
        }
        
        // Clear and perform copy command
        generalPasteboard.clearContents()
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // Wait for copy operation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let selectedText = generalPasteboard.string(forType: .string) ?? ""
            
            // Update app state with found image if any
            self.appState.selectedImages = foundImage.map { [$0] } ?? []
            
            // Restore original clipboard contents
            generalPasteboard.clearContents()
            if let oldContents = oldContents {
                generalPasteboard.setString(oldContents, forType: .string)
            }
            
            let popupWindow = PopupWindow(appState: self.appState)
            popupWindow.delegate = WindowManager.shared
            
            self.appState.selectedText = selectedText
            
            // Set appropriate window size based on content
            if !selectedText.isEmpty || !self.appState.selectedImages.isEmpty {
                popupWindow.setContentSize(NSSize(width: 400, height: 400))
            } else {
                popupWindow.setContentSize(NSSize(width: 400, height: 100))
            }
            
            popupWindow.positionNearMouse()
            NSApp.activate(ignoringOtherApps: true)
            popupWindow.makeKeyAndOrderFront(nil)
            popupWindow.orderFrontRegardless()
            
            // Hide the floating icon
            self.orderOut(nil)
        }
    }
    
    func positionNearSelection() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }
        
        let padding: CGFloat = 10
        var windowFrame = frame
        
        // Position to the right of the cursor
        windowFrame.origin.x = mouseLocation.x + padding
        windowFrame.origin.y = mouseLocation.y - (windowFrame.height / 2)
        
        // Keep window within screen bounds
        windowFrame.origin.x = min(windowFrame.origin.x,
                                 screen.visibleFrame.maxX - windowFrame.width - padding)
        windowFrame.origin.y = min(max(windowFrame.origin.y,
                                     screen.visibleFrame.minY + padding),
                                 screen.visibleFrame.maxY - windowFrame.height - padding)
        
        setFrame(windowFrame, display: true)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 1.0
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0.7
        }
    }
    
    func cleanup() {
        if let contentView = contentView,
           let trackingArea = trackingArea {
            contentView.removeTrackingArea(trackingArea)
        }
        self.trackingArea = nil
        self.contentView = nil
    }
    
    override func close() {
        cleanup()
        super.close()
    }
}
