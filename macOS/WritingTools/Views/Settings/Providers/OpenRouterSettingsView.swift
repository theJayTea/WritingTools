//
//  OpenRouterSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct OpenRouterSettingsView: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SecureAPIKeyField("API Key", text: $settings.openRouterApiKey)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

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
                }
            }
            .padding(.bottom, 4)

            Button("Get OpenRouter API Key") {
                if let url = URL(string: "https://openrouter.ai/keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Open OpenRouter to retrieve your API key.")
        }
    }
}
