//
//  OpenRouterProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct OpenRouterProviderSettingsView: View {
  @ObservedObject var settings: AppSettings

  var body: some View {
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
}
