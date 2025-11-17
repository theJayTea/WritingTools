//
//  GeminiProviderSettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct GeminiProviderSettingsView: View {
  @ObservedObject var settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure Google Gemini AI")
        .font(.headline)
      TextField("API Key", text: $settings.geminiApiKey)
        .textFieldStyle(.roundedBorder)

      Picker("Model", selection: $settings.geminiModel) {
        ForEach(GeminiModel.allCases, id: \.self) { model in
          Text(model.displayName).tag(model)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)

      if settings.geminiModel == .custom {
        TextField("Custom Model Name", text: $settings.geminiCustomModel)
          .textFieldStyle(.roundedBorder)
          .padding(.top, 4)
      }

      Button("Get Gemini API Key") {
        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.link)
    }
  }
}
