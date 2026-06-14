//
//  AIProviderSettingsPane.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct AIProviderSettingsPane: View {
    @Bindable var appState: AppState
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Text("Choose the AI service Writing Tools uses for commands and custom prompts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("AI Provider", selection: $settings.currentProvider) {
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
                .accessibilityLabel("AI Provider")
                .accessibilityHint("Select which AI service to use for processing.")
                .onChange(of: settings.currentProvider) { _, newValue in
                    if newValue == "local" && !LocalModelProvider.isAppleSilicon {
                        settings.currentProvider = "gemini"
                    }
                }
                .help("Select which AI service to use for processing.")
            } header: {
                Text("Provider")
            }

            Section {
                providerSettingsContent
            } header: {
                Text("Configuration")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var providerSettingsContent: some View {
        if settings.currentProvider == "gemini" {
            GeminiSettingsView()
        } else if settings.currentProvider == "mistral" {
            MistralSettingsView()
        } else if settings.currentProvider == "anthropic" {
            AnthropicSettingsView()
        } else if settings.currentProvider == "openai" {
            OpenAISettingsView()
        } else if settings.currentProvider == "ollama" {
            OllamaSettingsView()
        } else if settings.currentProvider == "openrouter" {
            OpenRouterSettingsView()
        } else if settings.currentProvider == "local" {
            LocalLLMSettingsView(provider: appState.localLLMProvider)
        }
    }
}
