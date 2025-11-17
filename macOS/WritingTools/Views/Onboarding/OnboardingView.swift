import SwiftUI
import ApplicationServices

@MainActor struct OnboardingView: View {
  @ObservedObject var appState: AppState
  @ObservedObject var settings = AppSettings.shared

  @State private var currentStep = 0
  @State private var isAccessibilityGranted = AXIsProcessTrusted()
  @State private var isScreenRecordingGranted =
    OnboardingPermissionsHelper.checkScreenRecording()
  @State private var wantsScreenshotOCR = false

  private let steps = [
    OnboardingStep(
      title: "Welcome to WritingTools",
      description: "Let's personalize your setup in a few quick steps.",
      isPermissionStep: false
    ),
    OnboardingStep(
      title: "Permissions",
      description:
        "Grant the required permission(s) so WritingTools can copy selections and paste results.",
      isPermissionStep: true
    ),
    OnboardingStep(
      title: "Customize",
      description:
        "Choose your global shortcut, theme, and AI provider. You can change these anytime in Settings.",
      isPermissionStep: false
    ),
    OnboardingStep(
      title: "All Set!",
      description:
        "You can always revisit Settings to change providers, shortcuts, or themes.",
      isPermissionStep: false
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(spacing: 6) {
        Text(steps[currentStep].title)
          .font(.largeTitle)
          .bold()
          .multilineTextAlignment(.center)
        Text(steps[currentStep].description)
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
      .padding(.top, 24)

      Divider().padding(.top, 16)

      // Body
      ScrollView {
        VStack(spacing: 20) {
          switch currentStep {
          case 0:
            OnboardingWelcomeStep()
          case 1:
            OnboardingPermissionsStep(
              isAccessibilityGranted: isAccessibilityGranted,
              isScreenRecordingGranted: isScreenRecordingGranted,
              wantsScreenshotOCR: wantsScreenshotOCR,
              onRefresh: refreshPermissionStatuses,
              onOpenPrivacyPane: openPrivacyPane
            )
          case 2:
            OnboardingCustomizationStep(appState: appState, settings: settings)
          case 3:
            OnboardingFinishStep(
              appState: appState,
              onOpenCommandsManager: openCommandsManager,
              onFinish: saveSettingsAndFinish
            )
          default:
            EmptyView()
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
      }

      Divider()

      // Footer
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          ForEach(0 ..< steps.count, id: \.self) { index in
            Circle()
              .fill(
                currentStep >= index
                  ? Color.accentColor
                  : Color.gray.opacity(0.3)
              )
              .frame(width: 10, height: 10)
          }
        }

        HStack {
          if currentStep > 0 {
            Button("Back") {
              withAnimation { currentStep -= 1 }
            }
            .buttonStyle(.bordered)
          }

          Spacer()

          if currentStep < steps.count - 1 {
            Button("Next") {
              withAnimation { currentStep += 1 }
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentStep == 1 && !isAccessibilityGranted)
          } else {
            Button("Finish") {
              saveSettingsAndFinish()
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(16)
      .background(Color(.windowBackgroundColor))
    }
    .frame(width: 640, height: 720)
    .background(
      Rectangle()
        .fill(Color.clear)
        .windowBackground(useGradient: settings.useGradientTheme)
    )
    .onAppear {
      refreshPermissionStatuses()
    }
  }

  private func refreshPermissionStatuses() {
    isAccessibilityGranted = AXIsProcessTrusted()
    isScreenRecordingGranted =
      OnboardingPermissionsHelper.checkScreenRecording()
  }

  private func openPrivacyPane(anchor: String) {
    if let url = URL(
      string:
        "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    ) {
      NSWorkspace.shared.open(url)
    }
  }

  private func openCommandsManager() {
    WindowManager.shared.transitonFromOnboardingToSettings(appState: appState)
  }

  @MainActor
  private func saveSettingsAndFinish() {
    switch settings.currentProvider {
    case "gemini":
      appState.saveGeminiConfig(
        apiKey: settings.geminiApiKey,
        model: settings.geminiModel,
        customModelName: settings.geminiCustomModel
      )
    case "mistral":
      appState.saveMistralConfig(
        apiKey: settings.mistralApiKey,
        baseURL: settings.mistralBaseURL,
        model: settings.mistralModel
      )
    case "openai":
      appState.saveOpenAIConfig(
        apiKey: settings.openAIApiKey,
        baseURL: settings.openAIBaseURL,
        organization: settings.openAIOrganization,
        project: settings.openAIProject,
        model: settings.openAIModel
      )
    case "anthropic":
      appState.saveAnthropicConfig(
        apiKey: settings.anthropicApiKey,
        model: settings.anthropicModel
      )
    case "openrouter":
      appState.saveOpenRouterConfig(
        apiKey: settings.openRouterApiKey,
        model: OpenRouterModel(rawValue: settings.openRouterModel) ?? .gpt4o,
        customModelName: settings.openRouterCustomModel
      )
    case "ollama":
      appState.saveOllamaConfig(
        baseURL: settings.ollamaBaseURL,
        model: settings.ollamaModel,
        keepAlive: settings.ollamaKeepAlive
      )
      UserDefaults.standard.set(
        settings.ollamaImageMode.rawValue,
        forKey: "ollama_image_mode"
      )
    default:
      break
    }

    appState.setCurrentProvider(settings.currentProvider)
    settings.hasCompletedOnboarding = true

    DispatchQueue.main.async {
      if let window = NSApplication.shared.windows.first(where: {
        $0.identifier?.rawValue == "OnboardingWindow"
      }) {
        window.close()
      }
    }
  }
}
