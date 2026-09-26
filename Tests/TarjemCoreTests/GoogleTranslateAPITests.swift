import XCTest
@testable import TarjemCore

final class GoogleTranslateAPITests: XCTestCase {
    func testRequestURLEncodesEverythingOutsideUnreservedSet() throws {
        let url = try XCTUnwrap(GoogleTranslateAPI.requestURL(text: "Tom & Jerry + 1=2?", source: "en", target: "ar"))
        XCTAssertEqual(
            url.absoluteString,
            "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ar&dt=t&q=Tom%20%26%20Jerry%20%2B%201%3D2%3F"
        )
    }

    func testParseJoinsSegmentsAndReadsDetectedLanguage() throws {
        let json = #"[[["مرحبا بالعالم. ","Hello world. ",null,null,10],["كيف حالك؟","How are you?",null,null,10]],null,"en",null,null,null,1,[],[["en"],null,[1],["en"]]]"#
        let result = try GoogleTranslateAPI.parse(Data(json.utf8))
        XCTAssertEqual(result.translation, "مرحبا بالعالم. كيف حالك؟")
        XCTAssertEqual(result.detectedSourceLanguage, "en")
    }

    func testParseRejectsHTMLErrorPages() {
        XCTAssertThrowsError(try GoogleTranslateAPI.parse(Data("<html>Sorry</html>".utf8))) { error in
            XCTAssertEqual(error as? GoogleTranslateAPI.ParseError, .invalidJSON)
        }
    }

    func testParseRejectsUnexpectedShape() {
        XCTAssertThrowsError(try GoogleTranslateAPI.parse(Data("[null]".utf8))) { error in
            XCTAssertEqual(error as? GoogleTranslateAPI.ParseError, .unexpectedFormat)
        }
    }
}
