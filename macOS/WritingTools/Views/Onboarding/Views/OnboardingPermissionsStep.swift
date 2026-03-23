//
//  OnboardingPermissionsStep.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import ApplicationServices
import CoreGraphics

struct OnboardingPermissionsStep: View {
  @Binding var isAccessibilityGranted: Bool
  @Binding var isScreenRecordingGranted: Bool
  @Binding var wantsScreenshotOCR: Bool

  var onRefresh: () -> Void
  var onOpenPrivacyPane: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Required")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

      PermissionRow(
        icon: "figure.wave.circle.fill",
        title: "Accessibility",
        status: isAccessibilityGranted ? .granted : .missing,
        explanation: """
          Required to simulate ⌘C/⌘V for copying your selection and \
          pasting results back into the original app. WritingTools does \
          not monitor your keystrokes.
          """,
        primaryActionTitle: isAccessibilityGranted ? "Granted" : "Request Access",
        secondaryActionTitle: "Open Settings",
        onPrimary: {
          OnboardingPermissionsHelper.requestAccessibility()
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            onRefresh()
          }
        },
        onSecondary: {
          onOpenPrivacyPane("Privacy_Accessibility")
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
          .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)
      .accessibilityLabel("Enable Screenshot OCR")
      .accessibilityHint("Requires Screen Recording permission to use OCR on screenshots.")

      if wantsScreenshotOCR {
        PermissionRow(
          icon: "rectangle.dashed.and.paperclip",
          title: "Screen Recording (Optional)",
          status: isScreenRecordingGranted ? .granted : .missing,
          explanation: """
            Required only if you use Screenshot OCR. macOS will show a \
            system prompt. You may need to restart the app for changes to \
            take effect. WritingTools does not record or store your \
            screen; it only uses this to capture the area you explicitly \
            select.
            """,
          primaryActionTitle: isScreenRecordingGranted ? "Granted" : "Request Access",
          secondaryActionTitle: "Open Settings",
          onPrimary: {
            OnboardingPermissionsHelper.requestScreenRecording { granted in
              isScreenRecordingGranted = granted
            }
          },
          onSecondary: {
            onOpenPrivacyPane("Privacy_ScreenCapture")
          }
        )
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text("Notes")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
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
          .foregroundStyle(.secondary)
        }
        .padding(8)
      }

      HStack {
        Button("Refresh Status") {
          onRefresh()
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Refresh permission status")
        .help("Recheck current permission statuses.")

        Spacer()

        Button("Open Privacy & Security") {
          OnboardingPermissionsHelper.openPrivacyPane()
        }
        .buttonStyle(.link)
        .accessibilityLabel("Open Privacy and Security settings")
        .help("Open System Settings to manage permissions.")
      }
      .padding(.top, 4)
    }
  }
}

// MARK: - Permission Helpers

struct OnboardingPermissionsHelper {
  /// Opens a Privacy & Security pane, trying the legacy `systempreferences:` scheme first
  /// (works on macOS 14–26+) and falling back to the `systemsettings:` scheme (macOS 13–15).
  @discardableResult
  static func openPrivacyPane(anchor: String? = nil) -> Bool {
    let suffix = anchor.map { "?\($0)" } ?? ""
    let urls = [
      "x-apple.systempreferences:com.apple.preference.security\(suffix)",
      "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension\(suffix)",
    ]
    for string in urls {
      if let url = URL(string: string), NSWorkspace.shared.open(url) {
        return true
      }
    }
    return false
  }

  static func requestAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as CFString
    let options: CFDictionary = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(200))
      openPrivacyPane(anchor: "Privacy_Accessibility")
    }
  }

  static func checkScreenRecording() -> Bool {
    CGPreflightScreenCaptureAccess()
  }

  static func requestScreenRecording(completion: @escaping (Bool) -> Void) {
    // CGRequestScreenCaptureAccess may present system UI, so it must run on the main thread.
    let granted = CGRequestScreenCaptureAccess()
    completion(granted)
  }
}
