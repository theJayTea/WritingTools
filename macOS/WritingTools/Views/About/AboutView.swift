import SwiftUI

private enum AboutURLs {
    static let emailJesai = URL(string: "mailto:jesaitarun@gmail.com")
    static let blissAI = URL(string: "https://play.google.com/store/apps/details?id=com.jesai.blissai")
    static let emailArya = URL(string: "mailto:developer@aryamirsepasi.com")
    static let proseKey = URL(string: "https://apps.apple.com/us/app/prosekey-ai/id6741180175")
    static let releases = URL(string: "https://github.com/theJayTea/WritingTools/releases")
}

struct AboutView: View {
    @Bindable private var settings = AppSettings.shared
    private var updateChecker = UpdateChecker.shared

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, let buildVersion, shortVersion != buildVersion {
            return "\(shortVersion) (\(buildVersion))"
        }

        return shortVersion ?? buildVersion ?? "Unknown"
    }

    @ViewBuilder
    private func safeLink(_ title: String, destination: URL?) -> some View {
        if let destination {
            Link(title, destination: destination)
                .buttonStyle(.link)
        } else {
            Text(title)
                .foregroundStyle(.secondary)
                .help("Link unavailable")
        }
    }
    
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
                    .foregroundStyle(.secondary)
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
                            safeLink("Email Jesai", destination: AboutURLs.emailJesai)
                            safeLink("Bliss AI on Google Play", destination: AboutURLs.blissAI)
                        }
                    }

                    Divider()

                    VStack(spacing: 2) {
                        Text("macOS version by Arya Mirsepasi")
                            .bold()
                        HStack(spacing: 12) {
                            safeLink("Email Arya", destination: AboutURLs.emailArya)
                            safeLink("ProseKey AI (iOS port)", destination: AboutURLs.proseKey)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Version and updates
            GroupBox("Version & Updates") {
                VStack(spacing: 8) {
                    Text("Version: \(appVersion)")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if updateChecker.isCheckingForUpdates {
                        ProgressView("Checking for updates...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let error = updateChecker.checkError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if updateChecker.updateAvailable {
                        Text("A new version is available!")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !updateChecker.hasCheckedForUpdates {
                        Text("Not checked yet.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("The latest version is already installed!")
                            .foregroundStyle(.green)
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

                        safeLink("View Releases", destination: AboutURLs.releases)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, idealWidth: 420, minHeight: 380, idealHeight: 420)
        .windowBackground(useGradient: settings.useGradientTheme)
    }
}
