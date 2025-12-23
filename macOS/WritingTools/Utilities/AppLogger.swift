import Foundation
import os

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "WritingTools"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
