import XCTest
@testable import TarjemCore

final class ColorSamplerTests: XCTestCase {
    /// Builds a `width`×`height` bitmap filled with `background`, with the pixels
    /// inside `glyphs` painted `foreground`.
    private func buffer(width: Int, height: Int, background: RGBA, foreground: RGBA, glyphs: CGRect) -> PixelBuffer {
        var data: [UInt8] = []
        data.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = glyphs.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) ? foreground : background
                data += [color.r, color.g, color.b, color.a]
            }
        }
        return PixelBuffer(width: width, height: height, bytesPerRow: width * 4, data: data)
    }

    func testDarkTextOnLightBackground() {
        let pixels = buffer(width: 100, height: 60, background: RGBA(250, 250, 245), foreground: RGBA(20, 20, 30),
                            glyphs: CGRect(x: 30, y: 25, width: 40, height: 10))
        let palette = ColorSampler.palette(in: pixels, rect: CGRect(x: 25, y: 20, width: 50, height: 20))
        XCTAssertEqual(palette.background, RGBA(250, 250, 245))
        XCTAssertEqual(palette.foreground, RGBA(20, 20, 30))
    }

    func testWhiteTextOnBlueButton() {
        let pixels = buffer(width: 100, height: 60, background: RGBA(0, 122, 255), foreground: .white,
                            glyphs: CGRect(x: 30, y: 25, width: 40, height: 10))
        let palette = ColorSampler.palette(in: pixels, rect: CGRect(x: 25, y: 20, width: 50, height: 20))
        XCTAssertEqual(palette.background, RGBA(0, 122, 255))
        XCTAssertEqual(palette.foreground, .white)
    }

    func testLowContrastFallsBackToReadableColor() {
        let pixels = buffer(width: 50, height: 30, background: RGBA(40, 40, 40), foreground: RGBA(55, 55, 55),
                            glyphs: CGRect(x: 10, y: 10, width: 30, height: 10))
        let palette = ColorSampler.palette(in: pixels, rect: CGRect(x: 5, y: 5, width: 40, height: 20))
        XCTAssertEqual(palette.foreground, .white)
    }

    func testRectOutsideImageFallsBackToDefaults() {
        let pixels = buffer(width: 10, height: 10, background: .black, foreground: .white, glyphs: .zero)
        let palette = ColorSampler.palette(in: pixels, rect: CGRect(x: 50, y: 50, width: 10, height: 10))
        XCTAssertEqual(palette, ColorSampler.Palette(background: .white, foreground: .black))
    }

    func testContrastRatio() {
        XCTAssertEqual(RGBA.black.contrast(with: .white), 21, accuracy: 0.01)
        XCTAssertEqual(RGBA.white.contrast(with: .white), 1, accuracy: 0.01)
    }
}
