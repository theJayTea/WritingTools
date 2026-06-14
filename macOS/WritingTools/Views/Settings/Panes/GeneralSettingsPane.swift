//
//  GeneralSettingsPane.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import KeyboardShortcuts
import AppKit

struct GeneralSettingsPane: View {
    @Bindable var appState: AppState
    @Bindable var settings = AppSettings.shared
    @Binding var showingCommandsManager: Bool

    var body: some View {
        Form {
            Section {
                Text("Set a global shortcut to quickly activate Writing Tools.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent("Activate Writing Tools:") {
                    KeyboardShortcuts.Recorder(for: .showPopup)
                        .accessibilityLabel("Activate Writing Tools shortcut")
                        .accessibilityHint("Sets the global shortcut to open Writing Tools.")
                        .help("Choose a convenient key combination to bring up Writing Tools from anywhere.")
                }
            } header: {
                Text("Keyboard Shortcuts")
            }

            Section {
                Text("Manage your writing tools and assign keyboard shortcuts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Manage Commands", systemImage: "list.bullet.rectangle") {
                    showingCommandsManager = true
                }
                .accessibilityLabel("Manage Commands")
                .accessibilityHint("Open the Commands Manager to add, edit, or remove commands.")
                .help("Open the Commands Manager to add, edit, or remove commands.")

                Toggle(isOn: $settings.openCustomCommandsInResponseWindow) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Open custom prompts in response window")
                        Text("When unchecked, custom prompts will replace selected text inline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel("Open custom prompts in response window")
                .accessibilityHint("When off, custom prompts replace selected text inline.")
                .help("Choose whether custom prompts open in a separate response window or replace text inline.")

                Toggle(isOn: $settings.enableICloudCommandSync) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sync commands with iCloud")
                        Text("Keep your command list in sync across your signed-in Apple devices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .help("Uses iCloud key-value storage to sync command edits across devices.")
            } header: {
                Text("Commands")
            }

            Section {
                Text("You can rerun the onboarding flow to review permissions and quickly configure the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    restartOnboarding()
                } label: {
                    Label("Restart Onboarding", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Restart onboarding")
                .accessibilityHint("Open the onboarding window to review permissions and setup.")
                .help("Open the onboarding window to set up WritingTools again.")
            } header: {
                Text("Onboarding")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingCommandsManager) {
            CommandsView(commandManager: appState.commandManager)
        }
    }

    private func restartOnboarding() {
        // Mark onboarding as not completed
        settings.hasCompletedOnboarding = false
        WindowManager.shared.showOnboarding(appState: appState, title: "Onboarding")
        NSApp.keyWindow?.close()
    }
}
