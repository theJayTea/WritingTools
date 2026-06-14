import XCTest
@testable import WritingTools

final class ResponseMarkdownRenderingTests: XCTestCase {
    func testStreamingMarkdownStripsPartialOuterMarkdownFence() {
        let partial = "```markdown\n# Title\nBody"

        XCTAssertEqual(
            partial.renderableMarkdownForResponse(isStreaming: true),
            "# Title\nBody"
        )
    }

    func testStreamingMarkdownBalancesUnclosedCodeFenceForDisplay() {
        let partial = "Here is code:\n\n```swift\nlet value = 1"

        XCTAssertEqual(
            partial.renderableMarkdownForResponse(isStreaming: true),
            "Here is code:\n\n```swift\nlet value = 1\n```"
        )
    }

    func testCompletedMarkdownStillUsesFinalNormalizationOnly() {
        let partial = "Here is code:\n\n```swift\nlet value = 1"

        XCTAssertEqual(
            partial.renderableMarkdownForResponse(isStreaming: false),
            partial
        )
    }
}
