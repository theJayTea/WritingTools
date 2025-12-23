//
//  AnthropicProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct AnthropicProviderSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
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
      .foregroundStyle(.secondary)

      Button("Get Anthropic API Key") {
        if let url = URL(string: "https://console.anthropic.com/settings/keys")
        {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }
}
