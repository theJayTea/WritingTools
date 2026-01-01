//
//  MistralSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct MistralSettingsView: View {
    @Bindable var settings = AppSettings.shared
    @Binding var needsSaving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("API Key", text: $settings.mistralApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.mistralApiKey) { _, _ in
                            needsSaving = true
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Picker("Model", selection: $settings.mistralModel) {
                        ForEach(MistralModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.mistralModel) { _, _ in
                        needsSaving = true
                    }
                }
            }
            .padding(.bottom, 4)
            
            Button("Get Mistral API Key") {
                if let url = URL(string: "https://console.mistral.ai/api-keys/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Open Mistral console to create an API key.")
        }
    }
}
