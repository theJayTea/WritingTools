import SwiftUI

class PopupWindow: NSWindow {
    private var initialLocation: NSPoint?
    private var retainedHostingView: NSHostingView<PopupView>?
    private var trackingArea: NSTrackingArea?
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        
        configureWindow()
        setupTrackingArea()
    }
    
    private func configureWindow() {
        backgroundColor = .clear
        isOpaque = false
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle]
        hasShadow = true
        isMovableByWindowBackground = true
        
        let closeAction: () -> Void = { [weak self] in
            self?.close()
            if let previousApp = self?.appState.previousApplication {
                previousApp.activate()
            }
        }
        
        let popupView = PopupView(appState: appState, closeAction: closeAction)
        let hostingView = NSHostingView(rootView: popupView)
        contentView = hostingView
        retainedHostingView = hostingView
        
        if appState.selectedText.isEmpty {
            setContentSize(NSSize(width: 400, height: 100))
        }
    }
    
    private func setupTrackingArea() {
        guard let contentView = contentView else { return }
        
        if let existing = trackingArea {
            contentView.removeTrackingArea(existing)
        }
        
        trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            contentView.addTrackingArea(trackingArea)
        }
    }
    
    func cleanup() {
        if let contentView = contentView,
           let trackingArea = trackingArea {
            contentView.removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        
        if let hostingView = retainedHostingView {
            hostingView.removeFromSuperview()
            self.retainedHostingView = nil
        }
        
        self.delegate = nil
        
        self.contentView = nil
    }
    
    override func close() {
        cleanup()
        super.close()
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // Mouse Event Handling
    override func mouseDown(with event: NSEvent) {
        //self.makeKey()
        initialLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let _ = contentView,
              let initialLocation = initialLocation,
              let screen = screen else { return }
        
        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - initialLocation.x
        let deltaY = currentLocation.y - initialLocation.y
        
        var newOrigin = frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        
        let padding: CGFloat = 20
        let screenFrame = screen.visibleFrame
        newOrigin.x = max(screenFrame.minX + padding,
                          min(newOrigin.x,
                              screenFrame.maxX - frame.width - padding))
        newOrigin.y = max(screenFrame.minY + padding,
                          min(newOrigin.y,
                              screenFrame.maxY - frame.height - padding))
        
        setFrameOrigin(newOrigin)
    }
    
    override func mouseUp(with event: NSEvent) {
        initialLocation = nil
    }
    
    
    // MARK: - Window Positioning
    
    // Find the screen where the mouse cursor is located
    func screenAt(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return nil
    }
    
    func positionNearMouse() {
        let mouseLocation = NSEvent.mouseLocation
        
        guard let screen = screenAt(point: mouseLocation) else { return }
        
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 10
        var windowFrame = frame
        
        windowFrame.origin.x = mouseLocation.x + padding
        windowFrame.origin.y = mouseLocation.y - windowFrame.height - padding
        
        if windowFrame.maxX > screenFrame.maxX {
            windowFrame.origin.x = mouseLocation.x - windowFrame.width - padding
        }
        
        if windowFrame.minY < screenFrame.minY {
            windowFrame.origin.y = mouseLocation.y + padding
        }
        
        windowFrame.origin.x = max(screenFrame.minX + padding, min(windowFrame.origin.x, screenFrame.maxX - windowFrame.width - padding))
        windowFrame.origin.y = max(screenFrame.minY + padding, min(windowFrame.origin.y, screenFrame.maxY - windowFrame.height - padding))
        
        setFrame(windowFrame, display: true)
    }
    
}

extension PopupWindow: NSWindowDelegate {
    /*func windowDidResignKey(_ notification: Notification) {
     close()
     }*/
    
    func windowDidBecomeKey(_ notification: Notification) {
        level = .popUpMenu
    }
}
