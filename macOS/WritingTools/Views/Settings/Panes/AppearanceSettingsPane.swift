//
//  AppearanceSettingsPane.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct AppearanceSettingsPane: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Text("Choose a window appearance that matches your preferences and context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Theme", selection: $settings.themeStyle) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Theme")
                .accessibilityHint("Choose how Writing Tools windows are styled.")
                .help("Standard uses system backgrounds. Glass respects transparency preferences. OLED uses deep blacks.")
            } header: {
                Text("Window Style")
            }
        }
        .formStyle(.grouped)
    }
}
