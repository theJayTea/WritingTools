import Foundation
import AppKit

@Observable
final class UpdateChecker: Sendable {
    static let shared = UpdateChecker()
    private let currentVersion = 1  // Current app version
    private let updateCheckURL = "https://raw.githubusercontent.com/theJayTea/WritingTools/main/macOS/Latest_Version_for_Update_Check.txt"
    private let updateDownloadURL = "https://github.com/theJayTea/WritingTools/releases"
    
    var isCheckingForUpdates = false
    var updateAvailable = false
    var checkError: String?
    
    private init() {}
    
    @MainActor
    func checkForUpdates() async {
        isCheckingForUpdates = true
        checkError = nil
        
        defer {
            isCheckingForUpdates = false
        }
        
        guard let url = URL(string: updateCheckURL) else {
            checkError = "Invalid update check URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Print raw data for debugging
            if let rawString = String(data: data, encoding: .utf8) {
                print("Raw version data: '\(rawString)'")
            }
            
            // Clean up the version string more aggressively
            let cleanedString = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            
            if let versionString = cleanedString,
               !versionString.isEmpty,
               let latestVersion = Int(versionString) {
                print("Parsed version: \(latestVersion)")
                updateAvailable = latestVersion > currentVersion
            } else {
                checkError = "Invalid version format"
                if let cleanedString = cleanedString {
                    print("Failed to parse version from: '\(cleanedString)'")
                }
            }
        } catch {
            checkError = "Failed to check for updates: \(error.localizedDescription)"
        }
    }
    
    func openReleasesPage() {
        if let url = URL(string: updateDownloadURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
