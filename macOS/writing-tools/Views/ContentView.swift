import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        EmptyView()
            .frame(width: 0, height: 0)
    }
}

