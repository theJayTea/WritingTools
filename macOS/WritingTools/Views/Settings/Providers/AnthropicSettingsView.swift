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
    @Binding var needsSaving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("API Key", text: $settings.anthropicApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.anthropicApiKey) { _, _ in needsSaving = true }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Picker("Model", selection: $settings.anthropicModel) {
                        ForEach(AnthropicModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.anthropicModel) { _, _ in needsSaving = true }
                    
                    TextField("Or Custom Model Name", text: $settings.anthropicModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onChange(of: settings.anthropicModel) { _, _ in needsSaving = true }
                    Text("E.g., \(AnthropicModel.claude45Haiku.rawValue), \(AnthropicModel.claude45Sonnet.rawValue), etc.")
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
    }
}
