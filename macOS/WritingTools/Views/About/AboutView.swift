import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            VStack(spacing: 6) {
                Text("About Writing Tools")
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Writing Tools is a free, lightweight utility that enhances your writing with AI.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .font(.title3)
                    .padding(.horizontal)
            }
            .padding(.top, 8)

            Divider()

            // Authors
            GroupBox("Creators") {
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Text("Created with care by Jesai, a high school student.")
                            .bold()
                        HStack(spacing: 12) {
                            Link("Email Jesai", destination: URL(string: "mailto:jesaitarun@gmail.com")!)
                            Link("Bliss AI on Google Play", destination: URL(string: "https://play.google.com/store/apps/details?id=com.jesai.blissai")!)
                        }
                    }

                    Divider()

                    VStack(spacing: 2) {
                        Text("macOS version by Arya Mirsepasi")
                            .bold()
                        HStack(spacing: 12) {
                            Link("Email Arya", destination: URL(string: "mailto:developer@aryamirsepasi.com")!)
                            Link("ProseKey AI (iOS port)", destination: URL(string: "https://apps.apple.com/us/app/prosekey-ai/id6741180175")!)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Version and updates
            GroupBox("Version & Updates") {
                VStack(spacing: 8) {
                    Text("Version: 5.3 (Based on Windows Port version 7.1)")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if updateChecker.isCheckingForUpdates {
                        ProgressView("Checking for updates...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let error = updateChecker.checkError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if updateChecker.updateAvailable {
                        Text("A new version is available!")
                            .foregroundColor(.green)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("The latest version is already installed!")
                            .foregroundColor(.green)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            if updateChecker.updateAvailable {
                                updateChecker.openReleasesPage()
                            } else {
                                Task { await updateChecker.checkForUpdates() }
                            }
                        }) {
                            Text(updateChecker.updateAvailable ? "Download Update" : "Check for Updates")
                        }
                        .buttonStyle(.borderedProminent)

                        Link("View Releases", destination: URL(string: "https://github.com/theJayTea/WritingTools/releases")!)
                            .buttonStyle(.link)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 420)
        .frame(minWidth: 400, minHeight: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowBackground(useGradient: settings.useGradientTheme)
    }
}
