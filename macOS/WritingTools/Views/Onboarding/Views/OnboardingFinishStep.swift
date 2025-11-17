//
//  OnboardingFinishStep.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct OnboardingFinishStep: View {
  var appState: AppState
  var onOpenCommandsManager: () -> Void
  var onFinish: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("You're ready to go!", systemImage: "checkmark.seal.fill")
            .font(.title2)
            .foregroundColor(.green)

          Text(
            """
            Press your global shortcut to open the popup. Select text or \
            images in any app and run a command. Built‑in commands are \
            available and you can add your own.
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
            "Use Proofread to preserve formatting while fixing grammar/spelling.",
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

      Text(
        "You can revisit onboarding anytime from Settings > General > Onboarding."
      )
      .font(.footnote)
      .foregroundColor(.secondary)

      HStack {
        Button("Open Commands Manager") {
          onOpenCommandsManager()
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Finish and Start Using WritingTools") {
          onFinish()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.top, 8)
    }
  }
}
