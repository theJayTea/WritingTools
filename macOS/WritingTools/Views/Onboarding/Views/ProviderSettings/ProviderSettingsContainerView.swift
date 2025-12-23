//
//  ProviderSettingsContainerView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct ProviderSettingsContainerView: View {
  @Bindable var settings: AppSettings
  @Bindable var appState: AppState

  @ViewBuilder
  var body: some View {
    switch settings.currentProvider {
    case "gemini":
      GeminiProviderSettingsView(settings: settings)
    case "mistral":
      MistralProviderSettingsView(settings: settings)
    case "anthropic":
      AnthropicProviderSettingsView(settings: settings)
    case "openai":
      OpenAIProviderSettingsView(settings: settings)
    case "ollama":
      OllamaProviderSettingsView(settings: settings)
    case "openrouter":
      OpenRouterProviderSettingsView(settings: settings)
    case "local":
      LocalLLMSettingsView(provider: appState.localLLMProvider)
    default:
      Text("Select a provider.")
        .foregroundColor(.secondary)
    }
  }
}
