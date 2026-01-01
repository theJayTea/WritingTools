import SwiftUI

@main
struct writing_toolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(width: 0, height: 0, alignment: .center)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
            ToolbarCommands()
        }
    }
}
