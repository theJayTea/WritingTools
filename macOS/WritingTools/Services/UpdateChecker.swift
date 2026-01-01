import Foundation
import AppKit
import Observation

private let logger = AppLogger.logger("UpdateChecker")

@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private let updateCheckURL = "https://raw.githubusercontent.com/theJayTea/WritingTools/main/macOS/Latest_Version_for_Update_Check.txt"
    private let updateDownloadURL = "https://github.com/theJayTea/WritingTools/releases"
    
    var isCheckingForUpdates = false
    var updateAvailable = false
    var checkError: String?

    private init() {}

    private var currentVersionString: String? {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return shortVersion ?? buildVersion
    }

    private func versionComponents(from version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let numericVersion = trimmed
            .components(separatedBy: allowed.inverted)
            .first(where: { !$0.isEmpty })

        guard let numericVersion, !numericVersion.isEmpty else {
            return nil
        }

        return numericVersion
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    private func isUpdateAvailable(current: String, latest: String) -> Bool? {
        guard let currentComponents = versionComponents(from: current),
              let latestComponents = versionComponents(from: latest) else {
            return nil
        }

        let maxCount = max(currentComponents.count, latestComponents.count)
        for index in 0..<maxCount {
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0
            let latestValue = index < latestComponents.count ? latestComponents[index] : 0
            if latestValue != currentValue {
                return latestValue > currentValue
            }
        }

        return false
    }
    
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
                logger.debug("Raw version data: '\(rawString)'")
            }
            
            let cleanedString = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let currentVersionString else {
                checkError = "Current version unavailable"
                return
            }

            if let versionString = cleanedString,
               !versionString.isEmpty,
               let hasUpdate = isUpdateAvailable(current: currentVersionString, latest: versionString) {
                logger.debug("Parsed version: \(versionString)")
                updateAvailable = hasUpdate
            } else {
                checkError = "Invalid version format"
                if let cleanedString = cleanedString {
                    logger.warning("Failed to parse version from: '\(cleanedString)'")
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
