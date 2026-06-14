import XCTest
@testable import WritingTools

final class MergeCommandsTests: XCTestCase {

    // MARK: - Helpers

    private func makeCommand(
        id: UUID = UUID(),
        name: String = "Test",
        prompt: String = "prompt",
        icon: String = "pencil",
        updatedAt: Date = .distantPast
    ) -> CommandModel {
        CommandModel(id: id, name: name, prompt: prompt, icon: icon, updatedAt: updatedAt)
    }

    // MARK: - Tests

    func testEmptyLocalAndRemoteReturnsEmptyList() {
        let result = CloudCommandsSync.mergeCommands(local: [], remote: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testRemoteOnlyCommandsAreIncluded() {
        let remoteCommand = makeCommand(name: "Remote Only")
        let result = CloudCommandsSync.mergeCommands(local: [], remote: [remoteCommand])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, remoteCommand.id)
    }

    func testLocalOnlyCommandsAreAppended() {
        let localCommand = makeCommand(name: "Local Only")
        let result = CloudCommandsSync.mergeCommands(local: [localCommand], remote: [])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, localCommand.id)
    }

    func testSharedCommandUsesRemoteVersionOnEqualTimestamps() {
        // Both sides default to `.distantPast`, so timestamps tie -> remote wins.
        let sharedId = UUID()
        let localVersion = makeCommand(id: sharedId, name: "Local Name", prompt: "local prompt")
        let remoteVersion = makeCommand(id: sharedId, name: "Remote Name", prompt: "remote prompt")

        let result = CloudCommandsSync.mergeCommands(local: [localVersion], remote: [remoteVersion])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Remote Name")
        XCTAssertEqual(result.first?.prompt, "remote prompt")
    }

    func testLocallyNewerCommandIsPreserved() {
        // Local was edited offline more recently than remote -> local must win
        // (this is the offline-edit data-loss fix).
        let sharedId = UUID()
        let localVersion = makeCommand(
            id: sharedId,
            name: "Local Name",
            prompt: "local prompt",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let remoteVersion = makeCommand(
            id: sharedId,
            name: "Remote Name",
            prompt: "remote prompt",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        let result = CloudCommandsSync.mergeCommands(local: [localVersion], remote: [remoteVersion])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Local Name")
        XCTAssertEqual(result.first?.prompt, "local prompt")
    }

    func testRemoteWinsWhenRemoteIsNewer() {
        let sharedId = UUID()
        let localVersion = makeCommand(
            id: sharedId,
            name: "Local Name",
            prompt: "local prompt",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let remoteVersion = makeCommand(
            id: sharedId,
            name: "Remote Name",
            prompt: "remote prompt",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let result = CloudCommandsSync.mergeCommands(local: [localVersion], remote: [remoteVersion])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Remote Name")
        XCTAssertEqual(result.first?.prompt, "remote prompt")
    }

    func testEqualNonDefaultTimestampsPreferRemote() {
        // Identical (non-distantPast) timestamps still tie -> remote wins.
        let sharedId = UUID()
        let stamp = Date(timeIntervalSince1970: 1_500)
        let localVersion = makeCommand(id: sharedId, name: "Local Name", updatedAt: stamp)
        let remoteVersion = makeCommand(id: sharedId, name: "Remote Name", updatedAt: stamp)

        let result = CloudCommandsSync.mergeCommands(local: [localVersion], remote: [remoteVersion])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Remote Name")
    }

    func testRemoteOrderingIsPreserved() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let remote = [
            makeCommand(id: id3, name: "Third"),
            makeCommand(id: id1, name: "First"),
            makeCommand(id: id2, name: "Second"),
        ]
        let local = [
            makeCommand(id: id1, name: "First Local"),
            makeCommand(id: id2, name: "Second Local"),
        ]

        let result = CloudCommandsSync.mergeCommands(local: local, remote: remote)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.id), [id3, id1, id2])
    }

    func testLocalOnlyCommandsAppendedAfterRemote() {
        let sharedId = UUID()
        let localOnlyId = UUID()

        let remote = [makeCommand(id: sharedId, name: "Shared Remote")]
        let local = [
            makeCommand(id: sharedId, name: "Shared Local"),
            makeCommand(id: localOnlyId, name: "Local Only"),
        ]

        let result = CloudCommandsSync.mergeCommands(local: local, remote: remote)

        XCTAssertEqual(result.count, 2)
        // Remote commands first, local-only appended
        XCTAssertEqual(result[0].id, sharedId)
        XCTAssertEqual(result[0].name, "Shared Remote")
        XCTAssertEqual(result[1].id, localOnlyId)
        XCTAssertEqual(result[1].name, "Local Only")
    }

    func testMergeWithDisjointSets() {
        let localId = UUID()
        let remoteId = UUID()

        let local = [makeCommand(id: localId, name: "Local")]
        let remote = [makeCommand(id: remoteId, name: "Remote")]

        let result = CloudCommandsSync.mergeCommands(local: local, remote: remote)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, remoteId)
        XCTAssertEqual(result[1].id, localId)
    }

    func testMergePreservesAllFieldsFromRemote() {
        let sharedId = UUID()
        let local = [makeCommand(id: sharedId, name: "Old")]
        let remote = [
            CommandModel(
                id: sharedId,
                name: "Updated",
                prompt: "new prompt",
                icon: "star",
                useResponseWindow: true,
                isBuiltIn: true,
                hasShortcut: true,
                preserveFormatting: true,
                providerOverride: "gemini",
                modelOverride: "flash"
            )
        ]

        let result = CloudCommandsSync.mergeCommands(local: local, remote: remote)

        XCTAssertEqual(result.count, 1)
        let merged = result[0]
        XCTAssertEqual(merged.name, "Updated")
        XCTAssertEqual(merged.prompt, "new prompt")
        XCTAssertEqual(merged.icon, "star")
        XCTAssertTrue(merged.useResponseWindow)
        XCTAssertTrue(merged.isBuiltIn)
        XCTAssertTrue(merged.hasShortcut)
        XCTAssertTrue(merged.preserveFormatting)
        XCTAssertEqual(merged.providerOverride, "gemini")
        XCTAssertEqual(merged.modelOverride, "flash")
    }
}
