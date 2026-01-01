//
//  OllamaProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct OllamaProviderSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
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
          .foregroundStyle(.secondary)
        Picker("Image Mode", selection: $settings.ollamaImageMode) {
          ForEach(OllamaImageMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Text("Use local OCR or Ollama's vision model for images.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      LinkText()

      Button("Ollama Documentation") {
        if let url = URL(string: "https://ollama.ai/download") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }
}
