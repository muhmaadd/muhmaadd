import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A paragraph-like group of OCR lines that should be translated together.
public struct TextBlock: Equatable, Sendable, Identifiable {
    public let id: Int
    public var text: String
    /// Union of the lines' rects, in image pixels (top-left origin).
    public var rect: CGRect
    public var lines: [OCRLine]
    /// Average height of the block's lines, in image pixels.
    public var lineHeight: CGFloat
    public var isTranslatable: Bool
}

/// Groups OCR lines into blocks (paragraphs, buttons, labels…).
///
/// Translating whole paragraphs instead of single lines gives the translator the
/// full sentence, which matters a lot for Arabic word order. Lines join a block
/// when they sit directly under its last line, have a similar text height and
/// overlap it horizontally, so side-by-side columns stay separate.
public struct TextBlockGrouper: Sendable {
    /// Maximum vertical gap between two lines of a block, relative to line height.
    public var maxLineGap: CGFloat = 0.9
    /// Maximum ratio between the heights of two consecutive lines of a block.
    public var maxHeightRatio: CGFloat = 1.5
    /// Lines recognized with a lower confidence are dropped as noise.
    public var minimumConfidence: Float = 0.3

    public init() {}

    public func group(_ lines: [OCRLine]) -> [TextBlock] {
        let usable = lines
            .filter { $0.confidence >= minimumConfidence }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { $0.rect.width > 0 && $0.rect.height > 0 }
            .sorted { lhs, rhs in
                if abs(lhs.rect.minY - rhs.rect.minY) > min(lhs.rect.height, rhs.rect.height) * 0.5 {
                    return lhs.rect.minY < rhs.rect.minY
                }
                return lhs.rect.minX < rhs.rect.minX
            }

        var groups: [[OCRLine]] = []
        for line in usable {
            var best: (index: Int, gap: CGFloat)?
            for (index, group) in groups.enumerated() {
                guard let gap = attachmentGap(of: line, to: group) else { continue }
                if best == nil || gap < best!.gap { best = (index, gap) }
            }
            if let best {
                groups[best.index].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups.enumerated().map { index, lines in
            let rect = lines.dropFirst().reduce(lines[0].rect) { $0.union($1.rect) }
            let text = TextTools.joinLines(lines.map(\.text))
            let lineHeight = lines.reduce(0) { $0 + $1.rect.height } / CGFloat(lines.count)
            return TextBlock(
                id: index,
                text: text,
                rect: rect,
                lines: lines,
                lineHeight: lineHeight,
                isTranslatable: TextTools.isTranslatable(text)
            )
        }
    }

    /// Returns the vertical gap between the group's last line and `line` when the
    /// line continues the group, or nil when it starts something new.
    private func attachmentGap(of line: OCRLine, to group: [OCRLine]) -> CGFloat? {
        guard let last = group.last else { return nil }
        let a = last.rect
        let b = line.rect

        let shorter = min(a.height, b.height)
        let taller = max(a.height, b.height)
        guard shorter > 0, taller / shorter <= maxHeightRatio else { return nil }

        let gap = b.minY - a.maxY
        // The new line must start below the previous one (small overlaps are
        // normal for tight line spacing) and not too far away.
        guard gap >= -shorter * 0.4, gap <= shorter * maxLineGap else { return nil }

        let groupRect = group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }
        let overlap = min(groupRect.maxX, b.maxX) - max(groupRect.minX, b.minX)
        guard overlap > min(b.width, groupRect.width) * 0.3 else { return nil }

        return gap
    }
}
