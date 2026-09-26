import XCTest
@testable import TarjemCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class TextBlockGrouperTests: XCTestCase {
    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 20) -> OCRLine {
        OCRLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height), confidence: 1)
    }

    func testParagraphLinesAreMergedIntoOneBlock() {
        let blocks = TextBlockGrouper().group([
            line("The quick brown fox jumps", x: 10, y: 10, width: 300),
            line("over the lazy dog.", x: 10, y: 34, width: 200),
        ])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].text, "The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(blocks[0].rect, CGRect(x: 10, y: 10, width: 300, height: 44))
        XCTAssertEqual(blocks[0].lineHeight, 20)
        XCTAssertTrue(blocks[0].isTranslatable)
    }

    func testDistantLinesStaySeparate() {
        let blocks = TextBlockGrouper().group([
            line("Title", x: 10, y: 10, width: 100),
            line("Body text far below", x: 10, y: 120, width: 200),
        ])
        XCTAssertEqual(blocks.map(\.text), ["Title", "Body text far below"])
    }

    func testSideBySideColumnsStaySeparate() {
        let blocks = TextBlockGrouper().group([
            line("Left column one", x: 10, y: 10, width: 150),
            line("Right column one", x: 400, y: 10, width: 150),
            line("Left column two", x: 10, y: 34, width: 150),
            line("Right column two", x: 400, y: 34, width: 150),
        ])
        XCTAssertEqual(blocks.map(\.text), [
            "Left column one Left column two",
            "Right column one Right column two",
        ])
    }

    func testHeadingWithDifferentSizeIsNotMergedWithBody() {
        let blocks = TextBlockGrouper().group([
            line("Big Heading", x: 10, y: 10, width: 300, height: 48),
            line("Small body text", x: 10, y: 62, width: 200, height: 16),
        ])
        XCTAssertEqual(blocks.count, 2)
    }

    func testLowConfidenceAndEmptyLinesAreDropped() {
        let blocks = TextBlockGrouper().group([
            OCRLine(text: "noise", rect: CGRect(x: 0, y: 0, width: 50, height: 10), confidence: 0.1),
            OCRLine(text: "   ", rect: CGRect(x: 0, y: 40, width: 50, height: 10), confidence: 1),
            OCRLine(text: "Keep me", rect: CGRect(x: 0, y: 80, width: 50, height: 10), confidence: 0.9),
        ])
        XCTAssertEqual(blocks.map(\.text), ["Keep me"])
    }

    func testBlocksAreInReadingOrderWithSequentialIDs() {
        let blocks = TextBlockGrouper().group([
            line("Second", x: 10, y: 200, width: 100),
            line("First", x: 10, y: 10, width: 100),
        ])
        XCTAssertEqual(blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(blocks.map(\.id), [0, 1])
    }

    func testNumbersAreNotTranslatable() {
        let blocks = TextBlockGrouper().group([line("12:45", x: 0, y: 0, width: 60)])
        XCTAssertFalse(blocks[0].isTranslatable)
    }

    func testVisionRectConversion() {
        let rect = VisionGeometry.imageRect(
            fromNormalized: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1),
            imageWidth: 1000,
            imageHeight: 500
        )
        XCTAssertEqual(rect.minX, 100, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 350, accuracy: 0.001)
        XCTAssertEqual(rect.width, 500, accuracy: 0.001)
        XCTAssertEqual(rect.height, 50, accuracy: 0.001)
    }
}
