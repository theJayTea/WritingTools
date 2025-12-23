//
//  AIProviderSettingsPane.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct AIProviderSettingsPane<SaveButton: View, CompleteSetupButton: View>: View {
    @Bindable var appState: AppState
    @Bindable var settings = AppSettings.shared
    @Binding var needsSaving: Bool
    var showOnlyApiSetup: Bool
    let saveButton: SaveButton
    let completeSetupButton: CompleteSetupButton

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Provider Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("Select AI Service")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Provider", selection: $settings.currentProvider) {
                    if LocalModelProvider.isAppleSilicon {
                        Text("Local LLM").tag("local")
                    }
                    Text("Gemini AI").tag("gemini")
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                    Text("Mistral AI").tag("mistral")
                    Text("Ollama").tag("ollama")
                    Text("OpenRouter").tag("openrouter")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: settings.currentProvider) { _, newValue in
                    if newValue == "local" && !LocalModelProvider.isAppleSilicon {
                        settings.currentProvider = "gemini"
                    }
                    needsSaving = true
                }
                .help("Select which AI service to use for processing.")
            }

            Divider()
                .padding(.vertical, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if settings.currentProvider == "gemini" {
                        GeminiSettingsView(needsSaving: $needsSaving)
                    } else if settings.currentProvider == "mistral" {
                        MistralSettingsView(needsSaving: $needsSaving)
                    } else if settings.currentProvider == "anthropic" {
                        AnthropicSettingsView(needsSaving: $needsSaving)
                    } else if settings.currentProvider == "openai" {
                        OpenAISettingsView(needsSaving: $needsSaving)
                    } else if settings.currentProvider == "ollama" {
                        OllamaSettingsView(needsSaving: $needsSaving)
                    } else if settings.currentProvider == "openrouter" {
                        OpenRouterSettingsView(needsSaving: $needsSaving)
                    } else if settings.currentProvider == "local" {
                        LocalLLMSettingsView(provider: appState.localLLMProvider)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !showOnlyApiSetup {
                saveButton
            } else {
                completeSetupButton
            }
        }
    }
}
