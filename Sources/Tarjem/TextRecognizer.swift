import CoreGraphics
import Foundation
import TarjemCore
import Vision

/// On-device OCR with Apple's Vision framework (the engine behind Live Text).
enum TextRecognizer {
    static func recognize(_ image: CGImage, detectLanguage: Bool) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if detectLanguage {
                    request.automaticallyDetectsLanguage = true
                } else {
                    request.recognitionLanguages = ["en-US"]
                }
                // Default is ~1/32 of the image height, which would skip normal UI
                // text in full-screen captures. Go down to ~9 pixels.
                request.minimumTextHeight = Float(min(1, 9 / Double(max(image.height, 1))))

                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                    let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return OCRLine(
                            text: candidate.string,
                            rect: VisionGeometry.imageRect(
                                fromNormalized: observation.boundingBox,
                                imageWidth: image.width,
                                imageHeight: image.height
                            ),
                            confidence: candidate.confidence
                        )
                    }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
