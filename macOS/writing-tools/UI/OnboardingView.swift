import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep = 0
    @State private var shortcutText = "⌃ Space"
    @State private var useGradientTheme = true
    @State private var selectedTheme = UserDefaults.standard.string(forKey: "theme_style") ?? "gradient"
    @State private var isShowingSettings = false
    
    private let steps = [
        OnboardingStep(
            title: "Welcome to WritingTools!",
            description: "Let's get you set up with just a few quick steps.",
            isPermissionStep: false
        ),
        OnboardingStep(
            title: "Enable Accessibility Access",
            description: "WritingTools needs accessibility access to detect text selection and enhance your writing experience.",
            isPermissionStep: true
        ),
        OnboardingStep(
            title: "Customize Your Experience",
            description: "Set up your preferred shortcut and theme.",
            isPermissionStep: false
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            VStack(spacing: 20) {
                // Step content
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    accessibilityStep
                case 2:
                    customizationStep
                default:
                    EmptyView()
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 20)
            
            // Bottom navigation area
            VStack(spacing: 16) {
                // Progress indicators
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(currentStep >= index ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Navigation buttons
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    Button(currentStep == steps.count - 1 ? "Finish" : "Next") {
                        if currentStep == steps.count - 1 {
                            saveSettingsAndContinue()
                        } else {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 500, height: 500)
        .onAppear {
            isShowingSettings = false
        }
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.accentColor)
            
            Text(steps[0].title)
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .center, spacing: 10) {
                Text("• Improves your writing with AI")
                Text("• Works in any application")
                Text("• Helps you write with clarity and confidence")
                Text("• Support Custom Commands for anything you want")
            }
            .font(.title3)
        }
    }
    
    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Text(steps[1].title)
                .font(.title)
                .bold()
            
            Text(steps[1].description)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("How to enable accessibility access:")
                    .font(.headline)
                
                Text("1. Click the button below to open System Settings")
                Text("2. Click the '+' button in the accessibility section")
                Text("3. Navigate to Applications and select writing-tools")
                Text("4. Enable the checkbox next to writing-tools")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var customizationStep: some View {
        VStack(spacing: 20) {
            Text("Customize Your Experience")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Set your keyboard shortcut:")
                    .font(.headline)
                
                KeyboardShortcuts.Recorder("Shortcut:", name: .showPopup)
                
                Section("Appearance") {
                    Picker("Theme", selection: $selectedTheme) {
                        Text("Standard").tag("standard")
                        Text("Gradient").tag("gradient")
                        Text("Glass").tag("glass")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedTheme) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "theme_style")
                        useGradientTheme = (newValue != "standard")
                    }
                }
            }
        }
    }
    
    
    private func saveSettingsAndContinue() {
        UserDefaults.standard.set(selectedTheme, forKey: "theme_style")
        UserDefaults.standard.set(selectedTheme != "standard", forKey: "use_gradient_theme")
        WindowManager.shared.transitonFromOnboardingToSettings(appState: appState)
    }
}

struct OnboardingStep {
    let title: String
    let description: String
    let isPermissionStep: Bool
}
