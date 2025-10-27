import SwiftUI
import KeyboardShortcuts
import ApplicationServices
import CoreGraphics

@MainActor struct OnboardingView: View {
  @ObservedObject var appState: AppState
  @ObservedObject var settings = AppSettings.shared

  @State private var currentStep = 0

  // Permissions
  @State private var isAccessibilityGranted = AXIsProcessTrusted()
  @State private var wantsScreenshotOCR = false
  @State private var isScreenRecordingGranted = OnboardingView.checkScreenRecording()

  private let steps = [
    OnboardingStep(
      title: "Welcome to WritingTools",
      description: "Let’s personalize your setup in a few quick steps.",
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
            welcomeStep
          case 1:
            permissionsStep
          case 2:
            customizationStep
          case 3:
            finishStep
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
        // Progress indicators
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

  // MARK: - Step 0: Welcome

  private var welcomeStep: some View {
    VStack(spacing: 16) {
      Image(systemName: "sparkles")
        .resizable()
        .scaledToFit()
        .frame(width: 60, height: 60)
        .foregroundColor(.accentColor)
        .padding(.bottom, 4)

      VStack(alignment: .leading, spacing: 10) {
        Label("Improve your writing with one shortcut", systemImage: "square.and.pencil")
        Label("Works in any app that supports copy & paste", systemImage: "app.badge")
        Label("Preserves formatting for supported apps", systemImage: "note.text")
        Label("Custom commands & per-command shortcuts", systemImage: "command.square.fill")
      }
      .font(.title3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 12)

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text("How it works")
            .font(.headline)
          Text(
            """
            WritingTools briefly copies your selection, sends it to your chosen \
            AI provider (or a local model), and then pastes the result back—\
            preserving formatting when supported.
            """
          )
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
      }

      Text("You can change any setting later in Settings.")
        .font(.footnote)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Step 1: Permissions

  private var permissionsStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Required")
        .font(.headline)

      PermissionRow(
        icon: "figure.wave.circle.fill",
        title: "Accessibility",
        status: isAccessibilityGranted ? .granted : .missing,
        explanation:
          """
          Required to simulate ⌘C/⌘V for copying your selection and pasting \
          results back into the original app. WritingTools does not monitor \
          your keystrokes.
          """,
        primaryActionTitle: isAccessibilityGranted ? "Granted" : "Request Access",
        secondaryActionTitle: "Open Settings",
        onPrimary: {
          // Prompt the system permission dialog
          OnboardingView.requestAccessibility()
          // Give System Settings a moment, then refresh
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshPermissionStatuses()
          }
        },
        onSecondary: {
          // Deep link to the correct pane
          openPrivacyPane(anchor: "Privacy_Accessibility")
        }
      )

      Divider().padding(.vertical, 4)

      Toggle(isOn: $wantsScreenshotOCR) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Enable Screenshot OCR (Optional)")
          Text(
            "If enabled, you can run OCR on screenshot snippets. This requires Screen Recording permission."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
      .toggleStyle(.switch)

      if wantsScreenshotOCR {
        PermissionRow(
          icon: "rectangle.dashed.and.paperclip",
          title: "Screen Recording (Optional)",
          status: isScreenRecordingGranted ? .granted : .missing,
          explanation:
            """
            Required only if you use Screenshot OCR. macOS will show a \
            system prompt. You may need to restart the app for changes to \
            take effect. WritingTools does not record or store your screen; \
            it only uses this to capture the area you explicitly select.
            """,
          primaryActionTitle: isScreenRecordingGranted ? "Granted" : "Request Access",
          secondaryActionTitle: "Open Settings",
          onPrimary: {
            OnboardingView.requestScreenRecording { granted in
              DispatchQueue.main.async {
                isScreenRecordingGranted = granted
              }
            }
          },
          onSecondary: {
            openPrivacyPane(anchor: "Privacy_ScreenCapture")
          }
        )
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text("Notes")
            .font(.headline)
          VStack(alignment: .leading, spacing: 6) {
            Label(
              "You can revoke any permission later in System Settings.",
              systemImage: "info.circle"
            )
            Label(
              "Input Monitoring is NOT required. WritingTools only posts copy/paste commands.",
              systemImage: "checkmark.circle"
            )
          }
          .foregroundColor(.secondary)
        }
        .padding(8)
      }

      HStack {
        Button("Refresh Status") {
          refreshPermissionStatuses()
        }
        .buttonStyle(.bordered)
        .help("Recheck current permission statuses.")

        Spacer()

        Button("Open Privacy & Security") {
          NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security")!
          )
        }
        .buttonStyle(.link)
        .help("Open System Settings to manage permissions.")
      }
      .padding(.top, 4)
    }
  }

  // MARK: - Step 2: Customize

  private var customizationStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      GroupBox("Global Shortcut") {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "Set the keyboard shortcut to activate WritingTools from anywhere."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          KeyboardShortcuts.Recorder(
            "Activate WritingTools:",
            name: .showPopup
          )
        }
        .padding(.vertical, 4)
      }

      GroupBox("Appearance Theme") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Choose how the popup window looks.")
            .font(.caption)
            .foregroundColor(.secondary)

          Picker("Theme", selection: $settings.themeStyle) {
            Text("Standard").tag("standard")
            Text("Gradient").tag("gradient")
            Text("Glass").tag("glass")
            Text("OLED").tag("oled")
          }
          .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
      }

      GroupBox("AI Provider") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Select the AI service you want to use.")
            .font(.caption)
            .foregroundColor(.secondary)

          Picker("Provider", selection: $settings.currentProvider) {
            if LocalModelProvider.isAppleSilicon {
              Text("Local LLM (On-Device)").tag("local")
            }
            Text("Gemini AI (Google)").tag("gemini")
            Text("OpenAI (ChatGPT)").tag("openai")
            Text("Mistral AI").tag("mistral")
            Text("Anthropic (Claude)").tag("anthropic")
            Text("Ollama (Self-Hosted)").tag("ollama")
            Text("OpenRouter").tag("openrouter")
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)
          .onChange(of: settings.currentProvider) { _, newValue in
            if newValue == "local", !LocalModelProvider.isAppleSilicon {
              settings.currentProvider = "gemini"
            }
          }

          // Provider-specific settings inline
          GroupBox("Provider Configuration") {
            providerSpecificSettings
          }
          .padding(.top, 8)

          Text("You can always adjust these later in Settings.")
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
      }
    }
  }

  // MARK: - Step 3: Finish

  private var finishStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("You’re ready to go!", systemImage: "checkmark.seal.fill")
            .font(.title2)
            .foregroundColor(.green)

          Text(
            """
            Press your global shortcut to open the popup. Select text or images \
            in any app and run a command. Built‑in commands are available and \
            you can add your own.
            """
          )
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
      }

      GroupBox("Tips") {
        VStack(alignment: .leading, spacing: 6) {
          Label(
            "Use “Proofread” to preserve formatting while fixing grammar/spelling.",
            systemImage: "text.badge.checkmark"
          )
          Label(
            "Assign per‑command shortcuts for instant actions without the popup.",
            systemImage: "keyboard"
          )
          Label(
            "Local LLM keeps data on‑device; cloud providers receive selected content for processing.",
            systemImage: "lock.shield"
          )
        }
        .foregroundColor(.secondary)
        .padding(8)
      }

      Text("You can revisit onboarding anytime from Settings > General > Onboarding.")
        .font(.footnote)
        .foregroundColor(.secondary)

      HStack {
        Button("Open Commands Manager") {
          WindowManager.shared.transitonFromOnboardingToSettings(
            appState: appState
          )
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Finish and Start Using WritingTools") {
          saveSettingsAndFinish()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.top, 8)
    }
  }

  // MARK: - Provider Specific Settings

  @ViewBuilder
  private var providerSpecificSettings: some View {
    switch settings.currentProvider {
    case "gemini":
      geminiSettings
    case "mistral":
      mistralSettings
    case "anthropic":
      anthropicSettings
    case "openai":
      openAISettings
    case "ollama":
      ollamaSettings
    case "openrouter":
      openRouterSettings
    case "local":
      LocalLLMSettingsView(provider: appState.localLLMProvider)
    default:
      Text("Select a provider.")
        .foregroundColor(.secondary)
    }
  }

  private var openRouterSettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure OpenRouter")
        .font(.headline)
      TextField("API Key", text: $settings.openRouterApiKey)
        .textFieldStyle(.roundedBorder)

      Picker("Model", selection: $settings.openRouterModel) {
        ForEach(OpenRouterModel.allCases, id: \.self) { model in
          Text(model.displayName).tag(model.rawValue)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)

      if settings.openRouterModel == OpenRouterModel.custom.rawValue {
        TextField("Custom Model Name", text: $settings.openRouterCustomModel)
          .textFieldStyle(.roundedBorder)
          .padding(.top, 4)
      }

      Button("Get OpenRouter API Key") {
        if let url = URL(string: "https://openrouter.ai/keys") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }

  private var geminiSettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure Google Gemini AI")
        .font(.headline)
      TextField("API Key", text: $settings.geminiApiKey)
        .textFieldStyle(.roundedBorder)

      Picker("Model", selection: $settings.geminiModel) {
        ForEach(GeminiModel.allCases, id: \.self) { model in
          Text(model.displayName).tag(model)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)

      if settings.geminiModel == .custom {
        TextField("Custom Model Name", text: $settings.geminiCustomModel)
          .textFieldStyle(.roundedBorder)
          .padding(.top, 4)
      }

      Button("Get Gemini API Key") {
        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }

  private var anthropicSettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure Anthropic (Claude)")
        .font(.headline)
      TextField("API Key", text: $settings.anthropicApiKey)
        .textFieldStyle(.roundedBorder)

      Picker("Model", selection: $settings.anthropicModel) {
        ForEach(AnthropicModel.allCases, id: \.self) { model in
          Text(model.displayName).tag(model.rawValue)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)

      TextField("Or Custom Model Name", text: $settings.anthropicModel)
        .textFieldStyle(.roundedBorder)
        .font(.caption)

      Text(
        "E.g., \(AnthropicModel.allCases.map { $0.rawValue }.joined(separator: ", "))"
      )
      .font(.caption)
      .foregroundColor(.secondary)

      Button("Get Anthropic API Key") {
        if let url = URL(string: "https://console.anthropic.com/settings/keys")
        {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }

  private var mistralSettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure Mistral AI")
        .font(.headline)
      TextField("API Key", text: $settings.mistralApiKey)
        .textFieldStyle(.roundedBorder)

      Picker("Model", selection: $settings.mistralModel) {
        ForEach(MistralModel.allCases, id: \.self) { model in
          Text(model.displayName).tag(model.rawValue)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)

      Button("Get Mistral API Key") {
        if let url = URL(string: "https://console.mistral.ai/api-keys/") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }

  private var openAISettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure OpenAI (ChatGPT)")
        .font(.headline)
      TextField("API Key", text: $settings.openAIApiKey)
        .textFieldStyle(.roundedBorder)

      TextField("Base URL (Optional)", text: $settings.openAIBaseURL)
        .textFieldStyle(.roundedBorder)

      TextField("Model Name", text: $settings.openAIModel)
        .textFieldStyle(.roundedBorder)

      Text(
        "Default models: \(OpenAIConfig.defaultModel), gpt-4o, gpt-4o-mini, etc."
      )
      .font(.caption)
      .foregroundColor(.secondary)

      Button("Get OpenAI API Key") {
        if let url = URL(
          string: "https://platform.openai.com/account/api-keys"
        ) {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }

  private var ollamaSettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure Ollama (Self-Hosted)")
        .font(.headline)
      TextField("Ollama Base URL", text: $settings.ollamaBaseURL)
        .textFieldStyle(.roundedBorder)

      TextField("Ollama Model Name", text: $settings.ollamaModel)
        .textFieldStyle(.roundedBorder)

      TextField("Keep Alive Time (e.g., 5m, 1h)", text: $settings.ollamaKeepAlive)
        .textFieldStyle(.roundedBorder)

      VStack(alignment: .leading, spacing: 6) {
        Text("Image Recognition Mode")
          .font(.subheadline)
          .foregroundColor(.secondary)
        Picker("Image Mode", selection: $settings.ollamaImageMode) {
          ForEach(OllamaImageMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Text("Use local OCR or Ollama's vision model for images.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      SettingsView.LinkText()

      Button("Ollama Documentation") {
        if let url = URL(string: "https://ollama.ai/download") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }

  // MARK: - Permission helpers

  private func refreshPermissionStatuses() {
    isAccessibilityGranted = AXIsProcessTrusted()
    isScreenRecordingGranted = OnboardingView.checkScreenRecording()
  }

  private func openPrivacyPane(anchor: String) {
    if let url = URL(
      string:
        "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    ) {
      NSWorkspace.shared.open(url)
    }
  }

  static func requestAccessibility() {
      // Request the system prompt (may no-op on recent macOS if already listed/denied)
      let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as CFString
      let options: CFDictionary = [key: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)

      // Always open Privacy > Accessibility as a reliable fallback
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
          NSWorkspace.shared.open(url)
        }
      }
    }
  

  static func checkScreenRecording() -> Bool {
    if #available(macOS 10.15, *) {
      return CGPreflightScreenCaptureAccess()
    } else {
      return true
    }
  }

  static func requestScreenRecording(completion: @escaping (Bool) -> Void) {
    if #available(macOS 10.15, *) {
      DispatchQueue.global(qos: .userInitiated).async {
        let granted = CGRequestScreenCaptureAccess()
        completion(granted)
      }
    } else {
      completion(true)
    }
  }

  // MARK: - Save & finish

  @MainActor private func saveSettingsAndFinish() {
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
      if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "OnboardingWindow" }) {
        window.close()
      } else if let window = NSApplication.shared.windows.first(where: { w in
        // Fallback: detect hosting view if identifier is missing
        if let _ = w.contentView as? NSHostingView<OnboardingView> { return true }
        return w.contentView?.subviews.contains(where: { $0 is NSHostingView<OnboardingView> }) ?? false
      }) {
        window.close()
      }
    }
  }
}

// MARK: - PermissionRow reusable view

private struct PermissionRow: View {
  enum Status {
    case granted
    case missing
  }

  let icon: String
  let title: String
  let status: Status
  let explanation: String
  let primaryActionTitle: String
  let secondaryActionTitle: String
  let onPrimary: () -> Void
  let onSecondary: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 28))
        .foregroundColor(status == .granted ? .green : .blue)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(title).font(.headline)
          Spacer()
          statusBadge
        }

        Text(explanation)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack {
          Button(primaryActionTitle, action: onPrimary)
            .buttonStyle(.borderedProminent)
            .disabled(status == .granted)

          Button(secondaryActionTitle, action: onSecondary)
            .buttonStyle(.bordered)

          Spacer()
        }
        .padding(.top, 4)
      }
    }
    .padding(12)
    .background(Color(.controlBackgroundColor))
    .cornerRadius(10)
  }

  @ViewBuilder
  private var statusBadge: some View {
    HStack(spacing: 6) {
      Image(
        systemName: status == .granted
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
      )
      .foregroundColor(status == .granted ? .green : .orange)
      Text(status == .granted ? "Granted" : "Required")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

// Keep the struct so existing code using steps still compiles
struct OnboardingStep {
  let title: String
  let description: String
  let isPermissionStep: Bool
}
