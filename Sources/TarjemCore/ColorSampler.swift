import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct RGBA: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(255, 255, 255)

    /// WCAG relative luminance (0 = black, 1 = white).
    public var luminance: Double {
        func linear(_ component: UInt8) -> Double {
            let c = Double(component) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio between two colors (1...21).
    public func contrast(with other: RGBA) -> Double {
        let l1 = luminance
        let l2 = other.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func distanceSquared(to other: RGBA) -> Int {
        let dr = Int(r) - Int(other.r)
        let dg = Int(g) - Int(other.g)
        let db = Int(b) - Int(other.b)
        return dr * dr + dg * dg + db * db
    }
}

/// A tightly packed RGBA8 bitmap whose first row is the top of the image.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let data: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int, data: [UInt8]) {
        precondition(bytesPerRow >= width * 4 && data.count >= bytesPerRow * height)
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.data = data
    }

    public func pixel(x: Int, y: Int) -> RGBA {
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        let offset = cy * bytesPerRow + cx * 4
        return RGBA(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }
}

/// Picks colors for drawing a translation over the original text, so the
/// overlay blends in like the original UI (dark text on light cards, white text
/// on colored buttons, …).
public enum ColorSampler {
    public struct Palette: Equatable, Sendable {
        public var background: RGBA
        public var foreground: RGBA

        public init(background: RGBA, foreground: RGBA) {
            self.background = background
            self.foreground = foreground
        }
    }

    public static func palette(in buffer: PixelBuffer, rect: CGRect) -> Palette {
        let bounds = CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        let inner = rect.intersection(bounds)
        guard !inner.isNull, inner.width >= 1, inner.height >= 1 else {
            return Palette(background: .white, foreground: .black)
        }

        let background = median(of: borderSamples(in: buffer, around: inner))
        var foreground = dominantContrastingColor(in: buffer, rect: inner, background: background)

        if foreground.contrast(with: background) < 3 {
            foreground = RGBA.black.contrast(with: background) >= RGBA.white.contrast(with: background)
                ? RGBA(17, 17, 17)
                : .white
        }
        return Palette(background: background, foreground: foreground)
    }

    /// Pixels on a ring just outside `rect` — usually pure background.
    static func borderSamples(in buffer: PixelBuffer, around rect: CGRect) -> [RGBA] {
        let pad = max(2, Int((rect.height * 0.1).rounded()))
        let minX = Int(rect.minX) - pad
        let maxX = Int(rect.maxX) + pad
        let minY = Int(rect.minY) - pad
        let maxY = Int(rect.maxY) + pad
        let stepX = max(1, (maxX - minX) / 60)
        let stepY = max(1, (maxY - minY) / 20)

        var samples: [RGBA] = []
        for x in stride(from: minX, through: maxX, by: stepX) {
            samples.append(buffer.pixel(x: x, y: minY))
            samples.append(buffer.pixel(x: x, y: maxY))
        }
        for y in stride(from: minY, through: maxY, by: stepY) {
            samples.append(buffer.pixel(x: minX, y: y))
            samples.append(buffer.pixel(x: maxX, y: y))
        }
        return samples
    }

    /// Averages the pixels inside `rect` that differ most from the background,
    /// which are the glyphs of the original text.
    static func dominantContrastingColor(in buffer: PixelBuffer, rect: CGRect, background: RGBA) -> RGBA {
        let columns = min(80, max(1, Int(rect.width)))
        let rows = min(24, max(1, Int(rect.height)))
        var samples: [(color: RGBA, distance: Int)] = []
        samples.reserveCapacity(columns * rows)
        for row in 0..<rows {
            let y = Int(rect.minY + (CGFloat(row) + 0.5) * rect.height / CGFloat(rows))
            for column in 0..<columns {
                let x = Int(rect.minX + (CGFloat(column) + 0.5) * rect.width / CGFloat(columns))
                let color = buffer.pixel(x: x, y: y)
                samples.append((color, color.distanceSquared(to: background)))
            }
        }
        samples.sort { $0.distance > $1.distance }
        let top = samples.prefix(max(1, samples.count / 8))
        guard let strongest = top.first, strongest.distance > 30 * 30 else { return background }
        return average(of: top.map(\.color))
    }

    static func median(of colors: [RGBA]) -> RGBA {
        guard !colors.isEmpty else { return .white }
        func mid(_ values: [UInt8]) -> UInt8 { values.sorted()[values.count / 2] }
        return RGBA(mid(colors.map(\.r)), mid(colors.map(\.g)), mid(colors.map(\.b)))
    }

    static func average(of colors: [RGBA]) -> RGBA {
        guard !colors.isEmpty else { return .black }
        let count = colors.count
        let r = colors.reduce(0) { $0 + Int($1.r) } / count
        let g = colors.reduce(0) { $0 + Int($1.g) } / count
        let b = colors.reduce(0) { $0 + Int($1.b) } / count
        return RGBA(UInt8(r), UInt8(g), UInt8(b))
    }
}
