//
//  OllamaSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct OllamaSettingsView: View {
    @Bindable var settings = AppSettings.shared
    @Binding var needsSaving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Settings")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Ollama Base URL", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.ollamaBaseURL) { _, _ in
                            needsSaving = true
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Ollama Model", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.ollamaModel) { _, _ in
                            needsSaving = true
                        }
                    
                    TextField("Keep Alive Time", text: $settings.ollamaKeepAlive)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.ollamaKeepAlive) { _, _ in
                            needsSaving = true
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Recognition")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Image Mode", selection: $settings.ollamaImageMode) {
                        ForEach(OllamaImageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.ollamaImageMode) { _, _ in
                        needsSaving = true
                    }
                    
                    Text("Choose between performing OCR locally or using an Ollama vision-enabled model for image input.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documentation")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LinkText()
                }
            }
            .padding(.bottom, 4)
            
            Button("Ollama Documentation") {
                if let url = URL(string: "https://ollama.ai/download") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Open Ollama download and documentation page in your browser.")
        }
    }
}
