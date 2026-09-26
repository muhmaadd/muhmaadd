import AppKit
import AVFoundation
import SwiftUI
import Translation

/// Floating window showing the translation as selectable text, with the
/// original, copy and read-aloud. Used for copied/selected text, for the
/// "panel" display mode and from the overlay's text button.
@MainActor
final class TextPanelController: NSObject, NSWindowDelegate {
    let job: TranslationJob
    var onClose: ((TextPanelController) -> Void)?

    private let panel: NSPanel

    init(job: TranslationJob) {
        self.job = job
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "ترجِم"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 340, height: 220)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TextPanelView(job: job, onClose: { [weak self] in self?.close() }))
    }

    func show() {
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        Speaker.shared.stop()
        onClose?(self)
    }

    /// Next to the mouse, kept on screen.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let visible = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame ?? .zero
        var frame = panel.frame
        frame.origin = CGPoint(x: mouse.x + 16, y: mouse.y - frame.height - 16)
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        panel.setFrame(frame, display: false)
    }
}

struct TextPanelView: View {
    @ObservedObject var job: TranslationJob
    let onClose: () -> Void

    @State private var showSource = false
    @State private var copied = false
    @ObservedObject private var speaker = Speaker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                Text(job.items.isEmpty ? " " : job.translatedText)
                    .font(.system(size: 17))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .redacted(reason: job.progress.done == 0 && job.isWorking ? .placeholder : [])
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            DisclosureGroup("النص الأصلي", isExpanded: $showSource) {
                ScrollView {
                    Text(job.sourceText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(8)
                }
                .frame(maxHeight: 140)
            }

            HStack {
                Button {
                    job.copyTranslation()
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                } label: {
                    Label(copied ? "تم النسخ" : "نسخ الترجمة", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    speaker.toggle(job.translatedText)
                } label: {
                    Label(speaker.isSpeaking ? "إيقاف" : "استماع", systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2")
                }

                Spacer()

                Button("إغلاق", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .disabled(job.progress.done == 0 && job.isWorking)
        }
        .padding(16)
        .padding(.top, 12)
        .frame(minWidth: 340, minHeight: 220)
        .environment(\.layoutDirection, .rightToLeft)
        .translationTask(job.appleConfiguration) { session in
            await job.runAppleTranslation(session)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            switch job.phase {
            case .recognizing:
                ProgressView().controlSize(.small)
                Text("جاري قراءة النص…").foregroundStyle(.secondary)
            case .translating:
                ProgressView().controlSize(.small)
                Text("جاري الترجمة…").foregroundStyle(.secondary)
            case .done:
                Image(systemName: "character.bubble.fill").foregroundStyle(Color.accentColor)
                Text("إنجليزي ← عربي")
                    .font(.headline)
                if let engine = job.engineUsed {
                    Text(engine.shortTitle)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .overlay(alignment: .bottomLeading) {
            if let notice = job.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .offset(y: 18)
            }
        }
        .padding(.bottom, job.notice == nil ? 0 : 14)
    }
}

/// Reads the Arabic translation aloud with a system Arabic voice.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        if isSpeaking {
            stop()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ar-SA")
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ar") }
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
