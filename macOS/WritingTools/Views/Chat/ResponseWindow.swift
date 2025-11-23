import SwiftUI

class ResponseWindow: NSWindow {
  private var hostingController: NSHostingController<ResponseView>?

  init(
    title: String,
    content: String,
    selectedText: String,
    option: WritingOption? = nil
  ) {
    let controller = NSHostingController(
      rootView: ResponseView(
        content: content,
        selectedText: selectedText,
        option: option
      )
    )
    self.hostingController = controller

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )

    self.title = title
    self.minSize = NSSize(width: 400, height: 300)
    self.isReleasedWhenClosed = false

    self.contentViewController = controller
    self.center()
    self.setFrameAutosaveName("ResponseWindow")
  }

  override func close() {
    WindowManager.shared.removeResponseWindow(self)
    super.close()
  }
}
