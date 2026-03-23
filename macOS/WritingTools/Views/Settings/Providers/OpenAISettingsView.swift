//
//  OpenAISettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct OpenAISettingsView: View {
    @Bindable var settings = AppSettings.shared
    @Binding var needsSaving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    SecureAPIKeyField("API Key", text: $settings.openAIApiKey)
                        .onChange(of: settings.openAIApiKey) { _, _ in
                            needsSaving = true
                        }
                    
                    TextField("Base URL (e.g. https://api.openai.com/v1)", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIBaseURL) { _, _ in
                            needsSaving = true
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("Model Name", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIModel) { _, _ in
                            needsSaving = true
                        }
                    
                    Text("OpenAI models include: gpt-4o, gpt-4o-mini, etc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Force Streaming", isOn: $settings.openAIForceStreaming)
                    .onChange(of: settings.openAIForceStreaming) { _, _ in
                        needsSaving = true
                    }
                    .help("Enable this if your API provider requires streaming responses (e.g. some third-party proxies).")
                
            }
            .padding(.bottom, 4)
            
            Button("Get OpenAI API Key") {
                if let url = URL(string: "https://platform.openai.com/account/api-keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Open OpenAI dashboard to create an API key.")
        }
    }
}
