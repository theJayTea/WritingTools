//
//  AppearanceSettingsPane.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct AppearanceSettingsPane: View {
    @Bindable var settings = AppSettings.shared
    @Binding var needsSaving: Bool
    var showOnlyApiSetup: Bool
    var saveButton: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Window Style")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Choose a window appearance that matches your preferences and context.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Theme", selection: $settings.themeStyle) {
                    Text("Standard").tag("standard")
                    Text("Gradient").tag("gradient")
                    Text("Glass").tag("glass")
                    Text("OLED").tag("oled")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
                .onChange(of: settings.themeStyle) { _, _ in
                    needsSaving = true
                }
                .help("Standard uses system backgrounds. Glass respects transparency preferences. OLED uses deep blacks.")
            }
            
            Spacer()
            
            if !showOnlyApiSetup {
                saveButton
            }
        }
    }
}
