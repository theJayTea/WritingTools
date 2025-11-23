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
    @ObservedObject var appState: AppState
    @ObservedObject var settings = AppSettings.shared
    @Binding var needsSaving: Bool
    @Binding var showingCommandsManager: Bool
    var showOnlyApiSetup: Bool
    var saveButton: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            GroupBox("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Set a global shortcut to quickly activate Writing Tools.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Activate Writing Tools:")
                            .frame(width: 180, alignment: .leading)
                            .foregroundColor(.primary)
                        KeyboardShortcuts.Recorder(
                            for: .showPopup,
                            onChange: { _ in
                                needsSaving = true
                            }
                        )
                        .help("Choose a convenient key combination to bring up Writing Tools from anywhere.")
                    }
                    .padding(.vertical, 2)
                }
            }

            GroupBox("Commands") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manage your writing tools and assign keyboard shortcuts.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button(action: {
                        showingCommandsManager = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                            Text("Manage Commands")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Open the Commands Manager to add, edit, or remove commands.")

                    Toggle(isOn: $settings.openCustomCommandsInResponseWindow) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open custom prompts in response window")
                            Text("When unchecked, custom prompts will replace selected text inline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
                    .onChange(of: settings.openCustomCommandsInResponseWindow) { _, _ in
                        needsSaving = true
                    }
                    .help("Choose whether custom prompts open in a separate response window or replace text inline.")
                }
            }
            
            GroupBox("Onboarding") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You can rerun the onboarding flow to review permissions and quickly configure the app.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    HStack {
                        Button {
                            restartOnboarding()
                        } label: {
                            Label("Restart Onboarding", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Open the onboarding window to set up WritingTools again.")

                        Spacer()
                    }
                }
            }

            Spacer()

            if !showOnlyApiSetup {
                saveButton
            }
        }
        .sheet(isPresented: $showingCommandsManager) {
            CommandsView(commandManager: appState.commandManager)
        }
    }

    private func restartOnboarding() {
        // Mark onboarding as not completed
        settings.hasCompletedOnboarding = false

        // Create the onboarding window the same way AppDelegate does
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Onboarding"
        window.isReleasedWhenClosed = false
        
        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .floating

        // Register with WindowManager properly
        WindowManager.shared.setOnboardingWindow(window, hostingView: hostingView)
        window.makeKeyAndOrderFront(nil)

        // Optionally close Settings to reduce window clutter
        if let settingsWindow = NSApplication.shared.windows.first(where: {
            $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) ?? false
        }) {
            settingsWindow.close()
        }
    }
}
