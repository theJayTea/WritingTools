import XCTest
import KeyboardShortcuts
@testable import WritingTools

final class CommandEditorTests: XCTestCase {
    func testTrimmedNameForSaveRemovesOuterWhitespace() {
        XCTAssertEqual(CommandEditor.trimmedNameForSave("  Proofread  "), "Proofread")
    }

    func testNormalizedNameCollapsesWhitespaceAndCase() {
        let normalized = CommandEditor.normalizedCommandName("  ProoF\n\t   Read   ")
        XCTAssertEqual(normalized, "proof read")
    }

    func testDuplicateNameDetectionIsWhitespaceAndCaseInsensitive() {
        let currentID = UUID()
        let existing = CommandModel(
            id: UUID(),
            name: "  Proof\nread  ",
            prompt: "prompt",
            icon: "pencil"
        )
        let current = CommandModel(
            id: currentID,
            name: "Current",
            prompt: "prompt",
            icon: "pencil"
        )

        let candidate = CommandEditor.normalizedCommandName("proof   READ")
        XCTAssertTrue(
            CommandEditor.hasDuplicateName(
                normalizedCandidateName: candidate,
                currentCommandID: currentID,
                existingCommands: [existing, current]
            )
        )
    }

    // MARK: - Empty Prompt Validation

    func testEmptyPromptIsRejected() {
        XCTAssertTrue(CommandEditor.isPromptEffectivelyEmpty(""))
        XCTAssertTrue(CommandEditor.isPromptEffectivelyEmpty("   \n\t  "))
    }

    func testNonEmptyPlainPromptIsAccepted() {
        XCTAssertFalse(CommandEditor.isPromptEffectivelyEmpty("Proofread this text."))
    }

    func testStructuredPromptWithBlankTaskIsRejected() {
        let json = """
        {
          "role": "assistant",
          "task": "   ",
          "rules": {
            "output": "only processed text",
            "preserve": { "language": "input" }
          }
        }
        """
        XCTAssertTrue(CommandEditor.isPromptEffectivelyEmpty(json))
    }

    func testStructuredPromptWithTaskIsAccepted() {
        let json = """
        {
          "role": "assistant",
          "task": "process the selected text",
          "rules": {
            "output": "only processed text",
            "preserve": { "language": "input" }
          }
        }
        """
        XCTAssertFalse(CommandEditor.isPromptEffectivelyEmpty(json))
    }

    // MARK: - hasShortcut Reflects Reality

    func testHasShortcutReflectsRecordedKey() {
        // Coverage: verifies that a freshly-created command UUID has no
        // registered keyboard shortcut, which is the precondition the editor
        // relies on before any shortcut is assigned.
        //
        // Limitation: CommandEditor.save() is a private instance method that
        // requires a live SwiftUI environment (sheet presentation, focus state,
        // etc.), so we cannot invoke it directly from a unit test without a
        // full UI host. Instead, we verify the underlying KeyboardShortcuts
        // lookup that the editor's `hasShortcut` computed property delegates to.
        // A UI/integration test would be required to cover the full save path.
        let id = UUID()
        let shortcutName = KeyboardShortcuts.Name.commandShortcut(for: id)

        // A brand-new UUID must have no shortcut registered in the system.
        XCTAssertNil(
            KeyboardShortcuts.getShortcut(for: shortcutName),
            "Expected no shortcut for a fresh command UUID before any assignment"
        )

        // Simulate what the editor does at save time: set then clear a shortcut.
        // This exercises the round-trip that `hasShortcut` is evaluated against.
        let testShortcut = KeyboardShortcuts.Shortcut(.f1)
        KeyboardShortcuts.setShortcut(testShortcut, for: shortcutName)
        XCTAssertNotNil(
            KeyboardShortcuts.getShortcut(for: shortcutName),
            "Shortcut should be retrievable immediately after assignment"
        )

        // Clean up: remove the shortcut so we don't pollute other test runs.
        KeyboardShortcuts.setShortcut(nil, for: shortcutName)
        XCTAssertNil(
            KeyboardShortcuts.getShortcut(for: shortcutName),
            "Shortcut should be nil after being explicitly cleared"
        )
    }

    // MARK: - preserveFormatting Sync

    func testPreserveFormattingSyncsFromStructuredPrompt() {
        // A structured prompt with preserve_formatting=true should make the
        // effective value true even when the stored flag starts false.
        let json = """
        {
          "role": "assistant",
          "task": "correct text",
          "rules": {
            "output": "only corrected text",
            "preserve": { "language": "input" },
            "preserve_formatting": true
          }
        }
        """
        var command = CommandModel(name: "Test", prompt: json, icon: "pencil")
        XCTAssertFalse(command.preserveFormatting)
        XCTAssertTrue(command.effectivePreserveFormatting)

        // Simulate the editor's save-time sync.
        command.preserveFormatting = command.effectivePreserveFormatting
        XCTAssertTrue(command.preserveFormatting)
        XCTAssertEqual(command.preserveFormatting, command.effectivePreserveFormatting)
    }

    func testPreserveFormattingStaysFalseForPlainPrompt() {
        var command = CommandModel(name: "Test", prompt: "Just plain text", icon: "pencil")
        command.preserveFormatting = command.effectivePreserveFormatting
        XCTAssertFalse(command.preserveFormatting)
    }
}
