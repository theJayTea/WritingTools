import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var shortcutText = "⌘ Space"
    @State private var useGradientTheme = true
    @State private var isShowingSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Writing Tools!")
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .center, spacing: 10) {
                Text("• Improves your writing with AI")
                Text("• Works in any application in just a click")
                Text("• Powered by Google's Gemini AI")
            }
            .font(.title3)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Customize your shortcut key:")
                    .font(.headline)
                
                ShortcutRecorderView(shortcutText: $shortcutText)
                    .frame(maxWidth: .infinity)
                
                Text("Theme:")
                    .font(.headline)
                
                Toggle("Use Gradient Theme", isOn: $useGradientTheme)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            Button("Next") {
                saveSettingsAndContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            isShowingSettings = false
        }
    }
    
    private func saveSettingsAndContinue() {
        UserDefaults.standard.set(shortcutText, forKey: "shortcut")
        UserDefaults.standard.set(useGradientTheme, forKey: "use_gradient_theme")
        
        WindowManager.shared.transitonFromOnboardingToSettings(appState: appState)
    }
}
