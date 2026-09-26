import AppKit
import TarjemCore
import Translation

/// One translation request: a screen capture (OCR → blocks → translation) or a
/// piece of text. The overlay and the text panel both observe it.
@MainActor
final class TranslationJob: ObservableObject {
    enum Phase: Equatable {
        case recognizing
        case translating
        case done
        case failed(String)
    }

    struct Item: Identifiable, Equatable, Sendable {
        let id: Int
        let source: String
        /// Where to draw the translation, in points relative to the capture's
        /// top-left corner. `.zero` for text jobs.
        let frame: CGRect
        let fontSize: CGFloat
        let translatable: Bool
        var background: RGBA
        var foreground: RGBA
        var translation: String?
    }

    let capture: CapturedImage?
    private let text: String?
    private let settings: AppSettings

    @Published private(set) var items: [Item] = []
    @Published private(set) var phase: Phase
    @Published private(set) var engineUsed: TranslationEngine?
    @Published private(set) var notice: String?
    /// Non-nil once Apple's engine should run; a view hosting
    /// `.translationTask` picks it up and calls `runAppleTranslation`.
    @Published private(set) var appleConfiguration: TranslationSession.Configuration?
    @Published var showOriginal = false
    @Published var isPinned = false

    private var started = false

    init(capture: CapturedImage, settings: AppSettings = .shared) {
        self.capture = capture
        self.text = nil
        self.settings = settings
        self.phase = .recognizing
    }

    init(text: String, settings: AppSettings = .shared) {
        self.capture = nil
        self.text = text
        self.settings = settings
        self.phase = .translating
    }

    var isWorking: Bool { phase == .recognizing || phase == .translating }

    var sourceText: String {
        items.map(\.source).joined(separator: "\n")
    }

    var translatedText: String {
        items.map { $0.translation ?? $0.source }.joined(separator: "\n")
    }

    var progress: (done: Int, total: Int) {
        let translatable = items.filter(\.translatable)
        return (translatable.filter { $0.translation != nil }.count, translatable.count)
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await run() }
    }

    func copyTranslation() {
        Pasteboard.copy(translatedText)
    }

    // MARK: - Pipeline

    private func run() async {
        if let capture {
            phase = .recognizing
            do {
                let lines = try await TextRecognizer.recognize(capture.image, detectLanguage: settings.sourceLanguage == .auto)
                let blocks = TextBlockGrouper().group(lines)
                items = await Self.makeItems(from: blocks, capture: capture)
            } catch {
                phase = .failed("تعذّرت قراءة النص: \(error.localizedDescription)")
                return
            }
        } else if let text {
            items = TextTools.paragraphs(text).enumerated().map { index, paragraph in
                Item(id: index, source: paragraph, frame: .zero, fontSize: 0,
                     translatable: TextTools.isTranslatable(paragraph),
                     background: .white, foreground: .black, translation: nil)
            }
        }

        guard items.contains(where: \.translatable) else {
            phase = .failed(items.isEmpty ? "لم يُعثر على أي نص." : "لم يُعثر على نص إنجليزي لترجمته.")
            return
        }
        phase = .translating

        switch settings.engine {
        case .apple:
            let source = settings.sourceLanguage == .english ? AppleTranslation.english : nil
            let sample = items.first(where: \.translatable)?.source ?? ""
            let status = await AppleTranslation.status(source: source, sample: sample)
            if status == .installed {
                let target = await AppleTranslation.arabic()
                engineUsed = .apple
                appleConfiguration = TranslationSession.Configuration(source: source, target: target)
            } else if settings.allowOnlineFallback {
                notice = status == .supported
                    ? "العربية غير منزّلة لترجمة Apple، فاستُخدم Google. نزّلها من الإعدادات للترجمة دون إنترنت."
                    : "ترجمة Apple غير متاحة لهذا النص، فاستُخدم Google."
                await translateWithGoogle()
            } else {
                phase = .failed("نزّل اللغة العربية لترجمة Apple من الإعدادات، أو فعّل الترجمة عبر Google.")
            }
        case .google:
            await translateWithGoogle()
        }
    }

    /// Called from the `.translationTask` of whichever view hosts the job.
    func runAppleTranslation(_ session: TranslationSession) async {
        let pending = items.filter { $0.translatable && $0.translation == nil }
        guard !pending.isEmpty else {
            finish()
            return
        }
        let requests = pending.map {
            TranslationSession.Request(sourceText: $0.source, clientIdentifier: String($0.id))
        }
        do {
            for try await response in session.translate(batch: requests) {
                guard let id = response.clientIdentifier.flatMap(Int.init) else { continue }
                setTranslation(response.targetText, for: id)
            }
            finish()
        } catch {
            // The hosting view went away (e.g. overlay → text panel); the next
            // host resumes with the remaining items.
            if Task.isCancelled || error is CancellationError { return }
            if settings.allowOnlineFallback {
                notice = "تعذّرت ترجمة Apple (\(error.localizedDescription))، فاستُخدم Google."
                await translateWithGoogle()
            } else {
                phase = .failed("تعذّرت الترجمة: \(error.localizedDescription)")
            }
        }
    }

    private func translateWithGoogle() async {
        engineUsed = .google
        let source = settings.sourceLanguage == .english ? "en" : "auto"
        let pending = items.filter { $0.translatable && $0.translation == nil }
        var lastError: Error?

        // A few requests at a time: fast, without hammering the endpoint.
        for start in stride(from: 0, to: pending.count, by: 4) {
            let batch = Array(pending[start..<min(start + 4, pending.count)])
            let results = await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
                for item in batch {
                    group.addTask {
                        do {
                            let translation = try await GoogleTranslator.shared.translate(item.source, from: source, to: "ar")
                            return (item.id, .success(translation))
                        } catch {
                            return (item.id, .failure(error))
                        }
                    }
                }
                var collected: [(Int, Result<String, Error>)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (id, result) in results {
                switch result {
                case .success(let translation): setTranslation(translation, for: id)
                case .failure(let error): lastError = error
                }
            }
        }

        if progress.done == 0, let lastError {
            phase = .failed("تعذّرت الترجمة عبر Google: \(lastError.localizedDescription)")
        } else {
            finish()
        }
    }

    private func setTranslation(_ translation: String, for id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].translation = translation
    }

    private func finish() {
        guard phase != .done else { return }
        let (done, total) = progress
        if done < total, notice == nil {
            notice = "تُرجم \(done) من \(total) مقطعاً."
        }
        phase = .done
        if settings.copyAutomatically { copyTranslation() }
    }

    /// Converts OCR blocks (image pixels) into overlay items (points) and picks
    /// colors that match the original UI. Runs off the main thread.
    private nonisolated static func makeItems(from blocks: [TextBlock], capture: CapturedImage) async -> [Item] {
        await Task.detached(priority: .userInitiated) {
            let pixels = PixelBuffer.make(from: capture.image)
            let bounds = CGRect(origin: .zero, size: capture.pointSize)
            return blocks.map { block in
                var palette = ColorSampler.Palette(background: .white, foreground: .black)
                if let pixels {
                    let rect = block.rect.applying(CGAffineTransform(scaleX: pixels.factor, y: pixels.factor))
                    palette = ColorSampler.palette(in: pixels.buffer, rect: rect)
                }
                let lineHeight = block.lineHeight / capture.scale
                let pad = max(1.5, lineHeight * 0.12)
                let frame = block.rect
                    .applying(CGAffineTransform(scaleX: 1 / capture.scale, y: 1 / capture.scale))
                    .insetBy(dx: -pad, dy: -pad)
                    .intersection(bounds)
                return Item(
                    id: block.id,
                    source: block.text,
                    frame: frame.isNull ? .zero : frame,
                    fontSize: max(9, lineHeight * 0.8),
                    translatable: block.isTranslatable,
                    background: palette.background,
                    foreground: palette.foreground,
                    translation: nil
                )
            }
        }.value
    }
}
