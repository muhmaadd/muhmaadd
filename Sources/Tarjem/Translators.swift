import Foundation
import TarjemCore
import Translation

enum TranslatorError: LocalizedError {
    case badResponse(Int)
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .badResponse(429): "رفض Google الطلب مؤقتاً بسبب كثرة الطلبات. حاول بعد قليل."
        case .badResponse(let code): "استجابة غير متوقعة من خدمة الترجمة (\(code))."
        case .invalidRequest: "تعذّر تجهيز طلب الترجمة."
        }
    }
}

/// Online engine using Google's public web endpoint.
actor GoogleTranslator {
    static let shared = GoogleTranslator()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        var parts: [String] = []
        for chunk in TextTools.chunks(text) {
            guard let url = GoogleTranslateAPI.requestURL(text: chunk, source: source, target: target) else {
                throw TranslatorError.invalidRequest
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw TranslatorError.badResponse(status) }
            parts.append(try GoogleTranslateAPI.parse(data).translation)
        }
        return parts.joined(separator: " ")
    }
}

/// Helpers around Apple's on-device Translation framework.
enum AppleTranslation {
    static let english = Locale.Language(identifier: "en")

    /// Apple lists Arabic with a region (e.g. ar-AE); pick whatever it supports.
    static func arabic() async -> Locale.Language {
        let supported = await LanguageAvailability().supportedLanguages
        return supported.first { $0.languageCode?.identifier == "ar" } ?? Locale.Language(identifier: "ar")
    }

    /// `.installed` means translation works offline right now; `.supported`
    /// means the language pack still has to be downloaded.
    static func status(source: Locale.Language?, sample: String) async -> LanguageAvailability.Status {
        let availability = LanguageAvailability()
        let target = await arabic()
        if let source {
            return await availability.status(from: source, to: target)
        }
        return (try? await availability.status(for: sample, to: target)) ?? .unsupported
    }
}
