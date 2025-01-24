import SwiftUI

struct AboutView: View {
    @State private var useGradientTheme = UserDefaults.standard.bool(forKey: "use_gradient_theme")
    @State private var updateChecker = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("About Writing Tools")
                .font(.largeTitle)
                .bold()
            
            Text("Writing Tools is a free & lightweight tool that helps you improve your writing with AI, similar to Apple's new Apple Intelligence feature.")
                .multilineTextAlignment(.center)
            
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
            }
            
            Divider()

            Text("Version: 1.0 (Based on Windows Port version 6.0)")
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
        .frame(width: 400, height: 400)
        .windowBackground(useGradient: useGradientTheme)
    }
}
