//
//  OnboardingCustomizationStep.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import KeyboardShortcuts

struct OnboardingCustomizationStep: View {
  @Bindable var appState: AppState
  @Bindable var settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      GroupBox("Global Shortcut") {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "Set the keyboard shortcut to activate WritingTools from anywhere."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

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
            .foregroundStyle(.secondary)

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
            .foregroundStyle(.secondary)

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

          GroupBox("Provider Configuration") {
            ProviderSettingsContainerView(settings: settings, appState: appState)
          }
          .padding(.top, 8)

          Text("You can always adjust these later in Settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
    }
  }
}
