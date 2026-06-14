//
//  AnthropicSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct AnthropicSettingsView: View {
    @Bindable var settings = AppSettings.shared
    @State private var modelSelection: AnthropicModel

    init() {
        // Initialize model selection from current settings to avoid flash on appear
        let currentModel = AppSettings.shared.anthropicModel
        if let knownModel = AnthropicModel(rawValue: currentModel), knownModel != .custom {
            self._modelSelection = State(initialValue: knownModel)
        } else {
            self._modelSelection = State(initialValue: .custom)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    SecureAPIKeyField("API Key", text: $settings.anthropicApiKey)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
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
                    Text("E.g., \(AnthropicModel.claude45Haiku.rawValue), \(AnthropicModel.claude46Sonnet.rawValue), etc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)
            
            Button("Get Anthropic API Key") {
                if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Open Anthropic console to create or view your API key.")
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
