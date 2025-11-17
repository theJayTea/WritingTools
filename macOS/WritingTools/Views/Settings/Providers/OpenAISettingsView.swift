//
//  OpenAISettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct OpenAISettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Binding var needsSaving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("API Key", text: $settings.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIApiKey) { _, _ in
                            needsSaving = true
                        }
                    
                    TextField("Base URL", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIBaseURL) { _, _ in
                            needsSaving = true
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Model Name", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIModel) { _, _ in
                            needsSaving = true
                        }
                    
                    Text("OpenAI models include: gpt-4o, gpt-4o-mini, etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
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
