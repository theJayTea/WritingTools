import Foundation

struct UnifiedCommand: Identifiable, Equatable {
    // For default commands we use the identifier from WritingOption (a localized String),
    // while for custom ones we use the CustomCommand id’s uuidString.
    var id: String
    var name: String
    var prompt: String
    var icon: String
    var useResponseWindow: Bool
    var isDefault: Bool
}
