//
//  AnthropicProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct AnthropicProviderSettingsView: View {
  @Bindable var settings: AppSettings
  @State private var modelSelection: AnthropicModel = .claude46Sonnet

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure Anthropic (Claude)")
        .font(.headline)
      SecureAPIKeyField("API Key", text: $settings.anthropicApiKey)

      Picker("Model", selection: $modelSelection) {
        ForEach(AnthropicModel.allCases, id: \.self) { model in
          Text(model.displayName).tag(model)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onChange(of: modelSelection) { _, newValue in
        if newValue != .custom {
          settings.anthropicModel = newValue.rawValue
        }
      }

      if modelSelection == .custom {
        TextField("Custom Model Name", text: $settings.anthropicModel)
          .textFieldStyle(.roundedBorder)
          .font(.caption)
      }

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
    .onAppear {
      syncModelSelection(settings.anthropicModel)
    }
    .onChange(of: settings.anthropicModel) { _, newValue in
      syncModelSelection(newValue)
    }
  }

  private func syncModelSelection(_ modelName: String) {
    if let knownModel = AnthropicModel(rawValue: modelName), knownModel != .custom {
      modelSelection = knownModel
    } else {
      modelSelection = .custom
    }
  }
}
