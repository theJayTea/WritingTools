import XCTest
@testable import WritingTools

final class CommandModelCodingTests: XCTestCase {

    // MARK: - Round-trip tests

    func testMinimalCommandRoundTrip() throws {
        let original = CommandModel(
            name: "Test",
            prompt: "Do something",
            icon: "pencil"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CommandModel.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.prompt, original.prompt)
        XCTAssertEqual(decoded.icon, original.icon)
        XCTAssertFalse(decoded.useResponseWindow)
        XCTAssertFalse(decoded.isBuiltIn)
        XCTAssertFalse(decoded.hasShortcut)
        XCTAssertFalse(decoded.preserveFormatting)
        XCTAssertFalse(decoded.isHidden)
        XCTAssertNil(decoded.providerOverride)
        XCTAssertNil(decoded.modelOverride)
        XCTAssertNil(decoded.customProviderBaseURL)
        XCTAssertNil(decoded.customProviderModel)
    }

    func testFullyPopulatedCommandRoundTrip() throws {
        let id = UUID()
        let original = CommandModel(
            id: id,
            name: "Full Command",
            prompt: "Do everything",
            icon: "star",
            useResponseWindow: true,
            isBuiltIn: true,
            hasShortcut: true,
            preserveFormatting: true,
            isHidden: true,
            providerOverride: "openai",
            modelOverride: "gpt-4o",
            customProviderBaseURL: "https://api.example.com",
            customProviderModel: "custom-model"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CommandModel.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Full Command")
        XCTAssertEqual(decoded.prompt, "Do everything")
        XCTAssertEqual(decoded.icon, "star")
        XCTAssertTrue(decoded.useResponseWindow)
        XCTAssertTrue(decoded.isBuiltIn)
        XCTAssertTrue(decoded.hasShortcut)
        XCTAssertTrue(decoded.preserveFormatting)
        XCTAssertTrue(decoded.isHidden)
        XCTAssertEqual(decoded.providerOverride, "openai")
        XCTAssertEqual(decoded.modelOverride, "gpt-4o")
        XCTAssertEqual(decoded.customProviderBaseURL, "https://api.example.com")
        XCTAssertEqual(decoded.customProviderModel, "custom-model")
    }

    func testArrayRoundTrip() throws {
        let commands = [
            CommandModel(name: "A", prompt: "a", icon: "a.circle"),
            CommandModel(name: "B", prompt: "b", icon: "b.circle", useResponseWindow: true),
        ]

        let data = try JSONEncoder().encode(commands)
        let decoded = try JSONDecoder().decode([CommandModel].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "A")
        XCTAssertEqual(decoded[1].name, "B")
        XCTAssertTrue(decoded[1].useResponseWindow)
    }

    // MARK: - Compact encoding (false booleans are omitted)

    func testFalseBoolsAreOmittedFromEncoding() throws {
        let command = CommandModel(
            name: "Compact",
            prompt: "test",
            icon: "pencil"
        )

        let data = try JSONEncoder().encode(command)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // False boolean fields should be omitted for compact storage
        XCTAssertNil(json?["useResponseWindow"])
        XCTAssertNil(json?["isBuiltIn"])
        XCTAssertNil(json?["hasShortcut"])
        XCTAssertNil(json?["preserveFormatting"])
        XCTAssertNil(json?["isHidden"])
        // Nil optionals should also be omitted
        XCTAssertNil(json?["providerOverride"])
        XCTAssertNil(json?["modelOverride"])
        XCTAssertNil(json?["customProviderBaseURL"])
        XCTAssertNil(json?["customProviderModel"])
        // updated_at is always encoded to support timestamp-based merge
        XCTAssertNotNil(json?["updated_at"])
    }

    func testTrueBoolsArePresent() throws {
        let command = CommandModel(
            name: "Full",
            prompt: "test",
            icon: "pencil",
            useResponseWindow: true,
            isBuiltIn: true,
            hasShortcut: true,
            preserveFormatting: true,
            isHidden: true
        )

        let data = try JSONEncoder().encode(command)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["useResponseWindow"] as? Bool, true)
        XCTAssertEqual(json?["isBuiltIn"] as? Bool, true)
        XCTAssertEqual(json?["hasShortcut"] as? Bool, true)
        XCTAssertEqual(json?["preserveFormatting"] as? Bool, true)
        XCTAssertEqual(json?["isHidden"] as? Bool, true)
    }

    // MARK: - Legacy data compatibility

    func testLegacyApiKeyFieldIsIgnoredDuringDecoding() throws {
        // Simulate JSON from an older version that included customProviderApiKey
        let legacyJSON: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Legacy",
            "prompt": "test",
            "icon": "pencil",
            "customProviderApiKey": "sk-secret-key",
        ]

        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        // Should decode without error — the legacy key is silently consumed
        let decoded = try JSONDecoder().decode(CommandModel.self, from: data)
        XCTAssertEqual(decoded.name, "Legacy")
    }

    func testMissingOptionalBoolsDefaultToFalse() throws {
        // Minimal JSON with only required fields
        let minimalJSON: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Minimal",
            "prompt": "test",
            "icon": "pencil",
        ]

        let data = try JSONSerialization.data(withJSONObject: minimalJSON)
        let decoded = try JSONDecoder().decode(CommandModel.self, from: data)

        XCTAssertFalse(decoded.useResponseWindow)
        XCTAssertFalse(decoded.isBuiltIn)
        XCTAssertFalse(decoded.hasShortcut)
        XCTAssertFalse(decoded.preserveFormatting)
        XCTAssertFalse(decoded.isHidden)
    }

    // MARK: - updatedAt timestamp

    func testMissingUpdatedAtDefaultsToDistantPast() throws {
        // JSON from before the updated_at field existed.
        let legacyJSON: [String: Any] = [
            "id": UUID().uuidString,
            "name": "NoTimestamp",
            "prompt": "test",
            "icon": "pencil",
        ]

        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(CommandModel.self, from: data)

        XCTAssertEqual(decoded.updatedAt, .distantPast)
    }

    func testUpdatedAtRoundTrips() throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = CommandModel(
            name: "Stamped",
            prompt: "test",
            icon: "pencil",
            updatedAt: stamp
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CommandModel.self, from: data)

        XCTAssertEqual(decoded.updatedAt, stamp)
    }

    // MARK: - Built-in IDs are stable

    func testBuiltInIDsAreStable() {
        XCTAssertEqual(CommandModel.BuiltInID.proofread.uuidString, "00000000-0001-0000-0000-000000000001")
        XCTAssertEqual(CommandModel.BuiltInID.rewrite.uuidString, "00000000-0001-0000-0000-000000000002")
        XCTAssertEqual(CommandModel.BuiltInID.friendly.uuidString, "00000000-0001-0000-0000-000000000003")
        XCTAssertEqual(CommandModel.BuiltInID.professional.uuidString, "00000000-0001-0000-0000-000000000004")
        XCTAssertEqual(CommandModel.BuiltInID.concise.uuidString, "00000000-0001-0000-0000-000000000005")
        XCTAssertEqual(CommandModel.BuiltInID.summary.uuidString, "00000000-0001-0000-0000-000000000006")
        XCTAssertEqual(CommandModel.BuiltInID.keyPoints.uuidString, "00000000-0001-0000-0000-000000000007")
        XCTAssertEqual(CommandModel.BuiltInID.table.uuidString, "00000000-0001-0000-0000-000000000008")
    }

    func testDefaultCommandsCountAndAllBuiltIn() {
        let defaults = CommandModel.defaultCommands
        XCTAssertEqual(defaults.count, 8)
        XCTAssertTrue(defaults.allSatisfy(\.isBuiltIn))
    }

    // MARK: - Equatable

    func testEqualityByAllFields() {
        let id = UUID()
        let a = CommandModel(id: id, name: "A", prompt: "p", icon: "i")
        let b = CommandModel(id: id, name: "A", prompt: "p", icon: "i")
        XCTAssertEqual(a, b)
    }

    func testInequalityWhenNameDiffers() {
        let id = UUID()
        let a = CommandModel(id: id, name: "A", prompt: "p", icon: "i")
        let b = CommandModel(id: id, name: "B", prompt: "p", icon: "i")
        XCTAssertNotEqual(a, b)
    }
}
