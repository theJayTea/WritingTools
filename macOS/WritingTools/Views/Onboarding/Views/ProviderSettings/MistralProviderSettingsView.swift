//
//  MistralProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct MistralProviderSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
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
}
