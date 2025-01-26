import SwiftUI

class PopupWindow: NSWindow {
    private var initialLocation: NSPoint?
    private var retainedHostingView: NSHostingView<PopupView>?
    private var trackingArea: NSTrackingArea?
    private let appState: AppState
    private let commandsManager: CustomCommandsManager
    
    init(appState: AppState) {
        self.appState = appState
        self.commandsManager = CustomCommandsManager()
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        
        self.isReleasedWhenClosed = false
        
        // Configure window after init
        configureWindow()
        setupTrackingArea()
        
        // Calculate and set correct size immediately
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowSize()
        }
        
        // Listen for changes in custom commands
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateWindowSize),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
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
        
        updateWindowSize()
    }
    
    @objc private func updateWindowSize() {
        let baseHeight: CGFloat = 100 // Height for header and input field
        let buttonHeight: CGFloat = 55 // Height for each button row
        let spacing: CGFloat = 16 // Vertical spacing between elements
        let padding: CGFloat = 20 // Bottom padding
        
        let numBuiltInOptions = WritingOption.allCases.count
        let numCustomOptions = commandsManager.commands.count
        let hasContent = !appState.selectedText.isEmpty || !appState.selectedImages.isEmpty
        let totalOptions = hasContent ? (numBuiltInOptions + numCustomOptions) : 0
        let numRows = ceil(Double(totalOptions) / 2.0) // 2 columns
        
        let contentHeight = !hasContent ?
        baseHeight :
        baseHeight + (buttonHeight * CGFloat(numRows)) + spacing + padding
        
        // Set size on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setContentSize(NSSize(width: 400, height: contentHeight))
            
            // Maintain window position relative to the mouse
            if let screen = self.screen {
                var frame = self.frame
                frame.size.height = contentHeight
                
                // Ensure window stays within screen bounds
                if frame.maxY > screen.visibleFrame.maxY {
                    frame.origin.y = screen.visibleFrame.maxY - frame.height
                }
                
                self.setFrame(frame, display: true)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
    
    
    // Window Positioning
    
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
