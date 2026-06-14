import SwiftUI

class ResponseWindow: NSWindow {
  private var hostingController: NSHostingController<ResponseView>?

  /// Shared autosave name so all response windows restore the same size/position.
  private static let sharedAutosaveName = "ResponseWindow"

  init(
    title: String,
    content: String,
    selectedText: String,
    option: WritingOption? = nil,
    provider: any AIProvider,
    continuationSystemPrompt: String? = nil
  ) {
    let controller = NSHostingController(
      rootView: ResponseView(
        content: content,
        selectedText: selectedText,
        option: option,
        provider: provider,
        continuationSystemPrompt: continuationSystemPrompt
      )
    )
    self.hostingController = controller

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    self.title = title
    self.minSize = NSSize(width: 400, height: 300)
    self.isReleasedWhenClosed = false
    configureThemedChrome()

    self.contentViewController = controller
    configureFrameRestoration()
  }

  /// Streaming initializer: opens immediately and streams the AI response inside the window.
  init(
    title: String,
    selectedText: String,
    option: WritingOption? = nil,
    provider: any AIProvider,
    systemPrompt: String,
    userPrompt: String,
    images: [Data],
    continuationSystemPrompt: String? = nil
  ) {
    let controller = NSHostingController(
      rootView: ResponseView(
        selectedText: selectedText,
        option: option,
        provider: provider,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        images: images,
        continuationSystemPrompt: continuationSystemPrompt
      )
    )
    self.hostingController = controller

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    self.title = title
    self.minSize = NSSize(width: 400, height: 300)
    self.isReleasedWhenClosed = false
    configureThemedChrome()

    self.contentViewController = controller
    configureFrameRestoration()
  }

  private func configureThemedChrome() {
    titlebarAppearsTransparent = true
    titlebarSeparatorStyle = .none
    isMovableByWindowBackground = true
  }

  private func configureFrameRestoration() {
    // Restore the last-used window size/position from the shared frame name.
    // We intentionally do NOT use setFrameAutosaveName here because each
    // response window is short-lived and creating unique autosave names
    // would leak UserDefaults entries. Instead, we manually restore/save
    // using a single shared key.
    if !self.setFrameUsingName(Self.sharedAutosaveName) {
      self.center()
    }
  }

  override func close() {
    // Persist this window's frame under the shared name so the next
    // response window opens at the same size/position.
    self.saveFrame(usingName: Self.sharedAutosaveName)
    WindowManager.shared.removeResponseWindow(self)
    super.close()
  }
}
