import XCTest
@testable import TarjemCore

final class TextToolsTests: XCTestCase {
    func testJoinLinesRepairsHyphenation() {
        XCTAssertEqual(TextTools.joinLines(["instant transla-", "tion tool"]), "instant translation tool")
    }

    func testJoinLinesKeepsRealDashes() {
        XCTAssertEqual(TextTools.joinLines(["Pages 10 -", "20"]), "Pages 10 - 20")
        XCTAssertEqual(TextTools.joinLines(["Built-", "In"]), "Built- In")
    }

    func testIsTranslatable() {
        XCTAssertTrue(TextTools.isTranslatable("OK"))
        XCTAssertTrue(TextTools.isTranslatable("Café"))
        XCTAssertFalse(TextTools.isTranslatable("A"))
        XCTAssertFalse(TextTools.isTranslatable("$4.99"))
        XCTAssertFalse(TextTools.isTranslatable("مرحبا بكم"))
        XCTAssertFalse(TextTools.isTranslatable("×÷"))
    }

    func testParagraphs() {
        let text = "First line\nstill first.\r\n\r\nSecond paragraph.\n\n\n"
        XCTAssertEqual(TextTools.paragraphs(text), ["First line still first.", "Second paragraph."])
    }

    func testShortTextIsSingleChunk() {
        XCTAssertEqual(TextTools.chunks("Hello there.", maxLength: 100), ["Hello there."])
    }

    func testChunksPreferSentenceBoundaries() {
        let text = "One two three. Four five six. Seven eight nine."
        let chunks = TextTools.chunks(text, maxLength: 32)
        XCTAssertEqual(chunks, ["One two three. Four five six.", "Seven eight nine."])
    }

    func testChunksNeverExceedLimit() {
        let word = String(repeating: "x", count: 25)
        let text = Array(repeating: "alpha beta gamma delta", count: 20).joined(separator: " ") + " " + word
        let chunks = TextTools.chunks(text, maxLength: 10)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 10 }, "\(chunks)")
        XCTAssertEqual(chunks.joined().filter { $0 != " " }, text.filter { $0 != " " })
    }
}
