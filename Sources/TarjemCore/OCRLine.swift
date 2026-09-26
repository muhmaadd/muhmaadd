import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One line of text found by OCR.
public struct OCRLine: Equatable, Sendable {
    public var text: String
    /// Bounding box in image pixels, origin at the top-left corner.
    public var rect: CGRect
    public var confidence: Float

    public init(text: String, rect: CGRect, confidence: Float = 1) {
        self.text = text
        self.rect = rect
        self.confidence = confidence
    }
}

public enum VisionGeometry {
    /// Converts a Vision bounding box (normalized 0...1, origin bottom-left) into
    /// image pixel coordinates with a top-left origin.
    public static func imageRect(fromNormalized box: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)
        return CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        )
    }
}
