import SwiftUI
import ApplicationServices

@MainActor struct OnboardingView: View {
  @Bindable var appState: AppState
  @Bindable var settings = AppSettings.shared
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.openSettings) private var openSettings

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
          .accessibilityAddTraits(.isHeader)
        Text(steps[currentStep].description)
          .font(.body)
          .foregroundStyle(.secondary)
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
              isAccessibilityGranted: $isAccessibilityGranted,
              isScreenRecordingGranted: $isScreenRecordingGranted,
              wantsScreenshotOCR: $wantsScreenshotOCR,
              onRefresh: refreshPermissionStatuses,
              onOpenPrivacyPane: openPrivacyPane
            )
          case 2:
            OnboardingCustomizationStep(appState: appState, settings: settings)
          case 3:
            OnboardingFinishStep(
              appState: appState,
              onConfigureProvider: openProviderSettings,
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
                  : Color.secondary.opacity(0.3)
              )
              .frame(width: 10, height: 10)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(steps.count)")

        HStack {
          if currentStep > 0 {
            Button("Back") {
              if reduceMotion {
                currentStep -= 1
              } else {
                withAnimation { currentStep -= 1 }
              }
            }
            .buttonStyle(.bordered)
          }

          Spacer()

          if currentStep < steps.count - 1 {
            Button("Next") {
              if reduceMotion {
                currentStep += 1
              } else {
                withAnimation { currentStep += 1 }
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentStep == 1 && (!isAccessibilityGranted || (wantsScreenshotOCR && !isScreenRecordingGranted)))
          } else {
            Button("Finish") {
              saveSettingsAndFinish()
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(16)
      .auxiliaryWindowSurface(useGradient: settings.useGradientTheme)
    }
    .frame(minWidth: 560, idealWidth: 640, maxWidth: 860, minHeight: 600, idealHeight: 720, maxHeight: 900)
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
        "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?\(anchor)"
    ) {
      NSWorkspace.shared.open(url)
    }
  }

  private func openProviderSettings() {
    // Mark onboarding complete so the app does not re-show it on next launch.
    settings.hasCompletedOnboarding = true

    // Close the onboarding window, then open the standard SwiftUI Settings
    // scene on the AI Provider pane (matching the prior "complete setup" intent).
    if let window = NSApplication.shared.windows.first(where: {
      $0.identifier?.rawValue == "OnboardingWindow"
    }) {
      window.close()
    }

    // Set the target tab before triggering the action so the pane restores correctly.
    UserDefaults.standard.set("AI Provider", forKey: "lastSettingsTab")

    // Capture existing windows before opening Settings, then use the SwiftUI
    // environment action (not the private `showSettingsWindow:` selector) and
    // let WindowManager raise the newly created Settings window to the front.
    let preexisting = Set(NSApplication.shared.windows.map(\.windowNumber))
    openSettings()
    WindowManager.shared.raiseSettingsWindow(excluding: preexisting)
  }

  @MainActor
  private func saveSettingsAndFinish() {
    // Use the unified save method from AppState
    appState.saveCurrentProviderSettings()
    settings.hasCompletedOnboarding = true

    if let window = NSApplication.shared.windows.first(where: {
      $0.identifier?.rawValue == "OnboardingWindow"
    }) {
      window.close()
    }
  }
}
