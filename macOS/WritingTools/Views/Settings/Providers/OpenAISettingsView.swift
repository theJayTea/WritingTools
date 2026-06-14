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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    SecureAPIKeyField("API Key", text: $settings.openAIApiKey)

                    TextField("Base URL (Optional)", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("Model Name", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)

                    Text("OpenAI models include: gpt-4o, gpt-4o-mini, etc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
