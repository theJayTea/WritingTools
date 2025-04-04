import SwiftUI
import Combine

class PopupWindow: NSWindow {
    private var initialLocation: NSPoint?
    private var retainedHostingView: NSHostingView<PopupView>?
    private var trackingArea: NSTrackingArea?
    private let appState: AppState
    private let windowWidth: CGFloat = 305  // Define fixed width
    private var commandCountCancellable: AnyCancellable?
    
    init(appState: AppState) {
        self.appState = appState
        
        super.init(
                    contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 100),
                    styleMask: [.borderless, .fullSizeContentView],
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
        
        // Set up observation of command changes using Combine
        commandCountCancellable = appState.commandManager.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowSize()
            }
        
        // Also observe notifications for immediate resize events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateWindowSize),
            name: NSNotification.Name("EditModeChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateWindowSize),
            name: NSNotification.Name("CommandsChanged"),
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
        let hostingView = FirstResponderHostingView(rootView: popupView) // Use custom view
        contentView = hostingView
        retainedHostingView = hostingView
        
        // Set up first responder
        self.initialFirstResponder = hostingView
        self.makeFirstResponder(hostingView)
        self.makeKey()
        
        updateWindowSize()
    }
    
    @objc private func updateWindowSize() {
        // Add a small delay to ensure view changes have settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            let baseHeight: CGFloat = 100 // Height for header and input field
            let buttonHeight: CGFloat = 55 // Height for each button row
            let spacing: CGFloat = 10 // Vertical spacing between elements
            let editButtonHeight: CGFloat = 60 // Height for the "Manage Commands" button
            
            // Get the total number of commands from the new CommandManager
            let totalCommands = self.appState.commandManager.commands.count
            let hasContent = !self.appState.selectedText.isEmpty || !self.appState.selectedImages.isEmpty
            let isEditMode = (self.retainedHostingView?.rootView as? PopupView)?.isEditMode ?? false
            
            // Calculate the number of rows (2 commands per row)
            let numRows = hasContent ? ceil(Double(totalCommands) / 2.0) : 0
            
            // Calculate content height
            var contentHeight: CGFloat = baseHeight
            
            if hasContent {
                contentHeight += (buttonHeight * CGFloat(numRows)) + spacing
                
                // Add height for the "Manage Commands" button if in edit mode
                if isEditMode {
                    contentHeight += editButtonHeight
                }
                
                // Add padding in edit mode
                if isEditMode {
                    contentHeight += 10
                }
            }
            
            print("Updating window size: Total commands: \(totalCommands), Rows: \(numRows), Edit mode: \(isEditMode), Height: \(contentHeight)")
            
            // Set size with animation
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                // Animate size change
                self.animator().setContentSize(NSSize(width: self.windowWidth, height: contentHeight))
                
                // Maintain window position relative to the mouse
                if let screen = self.screen {
                    var frame = self.frame
                    frame.size.height = contentHeight
                    
                    // Ensure window stays within screen bounds
                    if frame.maxY > screen.visibleFrame.maxY {
                        frame.origin.y = screen.visibleFrame.maxY - frame.height
                    }
                    
                    self.animator().setFrame(frame, display: true)
                }
            }
        }
    }
    
    deinit {
        commandCountCancellable?.cancel()
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
        commandCountCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
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
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }
            
            let padding: CGFloat = 10
            var windowFrame = frame
            windowFrame.size.width = windowWidth  // Ensure width stays fixed
            
            // Position below mouse by default
            windowFrame.origin.x = mouseLocation.x - (windowWidth / 2)  // Center horizontally on mouse
            windowFrame.origin.y = mouseLocation.y - windowFrame.height - padding
            
            // Keep window within screen bounds
            windowFrame.origin.x = max(screen.visibleFrame.minX + padding,
                                     min(windowFrame.origin.x,
                                         screen.visibleFrame.maxX - windowWidth - padding))
            
            if windowFrame.minY < screen.visibleFrame.minY {
                windowFrame.origin.y = mouseLocation.y + padding
            }
            
            setFrame(windowFrame, display: true)
        }
    
    // Close via ESC Key
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            self.close()
        } else {
            super.keyDown(with: event)
        }
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



class FirstResponderHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}
