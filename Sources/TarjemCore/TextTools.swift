import Foundation

public enum TextTools {
    /// Joins OCR lines of the same paragraph into one string, re-attaching words
    /// that were hyphenated across a line break ("transla-" + "tion").
    public static func joinLines(_ lines: [String]) -> String {
        var result = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !result.isEmpty else {
                result = line
                continue
            }
            let hyphenated = result.hasSuffix("-")
                && result.dropLast().last?.isLetter == true
                && line.first?.isLowercase == true
            if hyphenated {
                result.removeLast()
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }

    /// Number of Latin letters (A–Z plus accented Latin letters) in `text`.
    public static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            let value = scalar.value
            let isASCIILetter = (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
            let isAccentedLatin = (0xC0...0x24F).contains(value) && value != 0xD7 && value != 0xF7
            return count + (isASCIILetter || isAccentedLatin ? 1 : 0)
        }
    }

    /// Whether a piece of OCR text is worth sending to a translator. Numbers,
    /// times, prices, single letters and text that is already Arabic are kept as is.
    public static func isTranslatable(_ text: String) -> Bool {
        latinLetterCount(text) >= 2
    }

    /// Splits free text (e.g. from the clipboard) into paragraphs, keeping each
    /// paragraph's own line breaks out so every paragraph is translated in context.
    public static func paragraphs(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var paragraphs: [String] = []
        var current: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { paragraphs.append(joinLines(current)) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(joinLines(current)) }
        return paragraphs
    }

    /// Splits `text` into pieces no longer than `maxLength` characters, preferring
    /// sentence boundaries, then word boundaries.
    public static func chunks(_ text: String, maxLength: Int = 1500) -> [String] {
        precondition(maxLength > 0)
        guard text.count > maxLength else { return [text] }

        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?\n".contains(character) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        var chunks: [String] = []
        var chunk = ""
        func flush() {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            chunk = ""
        }
        for sentence in sentences {
            if chunk.count + sentence.count <= maxLength {
                chunk += sentence
                continue
            }
            flush()
            if sentence.count <= maxLength {
                chunk = sentence
                continue
            }
            // A single very long sentence: split on spaces, hard-split huge words.
            for word in sentence.split(separator: " ", omittingEmptySubsequences: false) {
                var piece = String(word)
                while piece.count > maxLength {
                    flush()
                    chunks.append(String(piece.prefix(maxLength)))
                    piece = String(piece.dropFirst(maxLength))
                }
                if chunk.count + piece.count + 1 > maxLength { flush() }
                chunk += chunk.isEmpty ? piece : " " + piece
            }
        }
        flush()
        return chunks
    }
}
