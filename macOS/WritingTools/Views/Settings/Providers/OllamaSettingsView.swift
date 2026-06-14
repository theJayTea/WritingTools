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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                // Connection & Model Configuration combined
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection & Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Base URL", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        TextField("Model", text: $settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)

                        TextField("Keep Alive", text: $settings.ollamaKeepAlive)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                // Image Recognition
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Recognition")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Image Mode", selection: $settings.ollamaImageMode) {
                        ForEach(OllamaImageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Use OCR locally or a vision-enabled model for images.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            // Documentation
            HStack(spacing: 12) {
                LinkText()

                Button("Ollama Docs") {
                    if let url = URL(string: "https://docs.ollama.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .help("Open Ollama download and documentation page.")
            }
        }
    }
}
