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
    var hasCheckedForUpdates = false

    private init() {}

    private var currentVersionString: String? {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return shortVersion ?? buildVersion
    }

    nonisolated static func versionComponents(from version: String) -> [Int]? {
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

    nonisolated static func isUpdateAvailable(current: String, latest: String) -> Bool? {
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
            hasCheckedForUpdates = true
        }
        
        guard let url = URL(string: updateCheckURL) else {
            checkError = "Invalid update check URL"
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)

            // Reject anything that isn't a clean 200. A 404/5xx returns an HTML
            // error page whose body could otherwise be mis-parsed as a version
            // number (e.g. the "404" in the status text), producing a bogus
            // "update available" or suppressing a real one.
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                checkError = "Update check failed (HTTP \(code))"
                logger.warning("Update check returned non-200 status: \(code)")
                return
            }

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
               let hasUpdate = Self.isUpdateAvailable(current: currentVersionString, latest: versionString) {
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
