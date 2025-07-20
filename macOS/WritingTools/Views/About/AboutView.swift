import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared
    
    var body: some View {
            VStack(spacing: 10) {
                HStack {
                    WindowControlButtons()
                    Spacer()
                }
                .contentShape(Rectangle())
                
                VStack(spacing: 10) {
                    
                    Text("About Writing Tools")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Writing Tools is a free & lightweight tool that helps you improve your writing with AI, similar to Apple's new Apple Intelligence feature.")
                        .multilineTextAlignment(.center)
                    
                }
                VStack(spacing: 10) {
                    Text("Created with care by Jesai, a high school student.")
                        .bold()
                    
                    Link("Email: jesaitarun@gmail.com",
                         destination: URL(string: "mailto:jesaitarun@gmail.com")!)
                    
                    Link("Check out Bliss AI on Google Play",
                         destination: URL(string: "https://play.google.com/store/apps/details?id=com.jesai.blissai")!)
                }
                
                Divider()
                
                VStack(spacing: 10) {
                    Text("The macOS version is created by Arya Mirsepasi")
                        .bold()
                    
                    Link("Email: developer@aryamirsepasi.com",
                         destination: URL(string: "mailto:developer@aryamirsepasi.com")!)
                    
                    Link("Check out ProseKey AI (iOS port of WritingTools)",
                         destination: URL(string: "https://apps.apple.com/us/app/prosekey-ai/id6741180175")!)
                }
                
                Divider()
                
                Text("Version: 5.0 (Based on Windows Port version 7.1)")
                    .font(.caption)
                
                // Update checker section
                VStack(spacing: 8) {
                    if updateChecker.isCheckingForUpdates {
                        ProgressView("Checking for updates...")
                    } else if let error = updateChecker.checkError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    } else if updateChecker.updateAvailable {
                        Text("A new version is available!")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if !updateChecker.updateAvailable {
                        Text("The latest version is already installed!")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    Button(action: {
                        if updateChecker.updateAvailable {
                            updateChecker.openReleasesPage()
                        } else {
                            Task {
                                await updateChecker.checkForUpdates()
                            }
                        }
                    }) {
                        Text(updateChecker.updateAvailable ? "Download Update" : "Check for Updates")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        .frame(width: 400, height: 380)
                .frame(minWidth: 400,
                       minHeight: 380)
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity)
        .windowBackground(useGradient: settings.useGradientTheme)
        .ignoresSafeArea(.container, edges: [.top,.bottom])
    }
}
