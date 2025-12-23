//
//  OpenAIProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct OpenAIProviderSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
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
}
