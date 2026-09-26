import Foundation

/// Request building and response parsing for Google's public web translation
/// endpoint (`translate.googleapis.com/translate_a/single?client=gtx`).
///
/// This endpoint needs no API key but is unofficial: Google may rate-limit it or
/// change it, so Tarjem only uses it as the online engine / fallback.
public enum GoogleTranslateAPI {
    public enum ParseError: Error, Equatable {
        case invalidJSON
        case unexpectedFormat
    }

    public struct Result: Equatable, Sendable {
        public var translation: String
        public var detectedSourceLanguage: String?
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func requestURL(text: String, source: String, target: String) -> URL? {
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
        }
        let query = [
            "client=gtx",
            "sl=\(encode(source))",
            "tl=\(encode(target))",
            "dt=t",
            "q=\(encode(text))",
        ].joined(separator: "&")
        return URL(string: "https://translate.googleapis.com/translate_a/single?\(query)")
    }

    /// Parses a response shaped like
    /// `[[["مرحبا","Hello",null,null,10], …], null, "en", …]`.
    public static func parse(_ data: Data) throws -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ParseError.invalidJSON
        }
        guard let segments = root.first as? [Any] else {
            throw ParseError.unexpectedFormat
        }
        let translation = segments
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
        guard !translation.isEmpty else { throw ParseError.unexpectedFormat }
        let detected = root.count > 2 ? root[2] as? String : nil
        return Result(translation: translation, detectedSourceLanguage: detected)
    }
}
