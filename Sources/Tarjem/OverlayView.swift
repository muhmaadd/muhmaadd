import SwiftUI
import Translation

/// Frozen screenshot of the captured area with each English block painted over
/// by its Arabic translation, like Google Lens / Apple's Live Text translate.
struct OverlayView: View {
    @ObservedObject var job: TranslationJob
    let capture: CapturedImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .frame(width: capture.pointSize.width, height: capture.pointSize.height)

            if !job.showOriginal {
                ForEach(job.items.filter { $0.translation != nil }) { item in
                    TranslatedBlock(item: item)
                        .offset(x: item.frame.minX, y: item.frame.minY)
                        .transition(.opacity)
                }
            }

            if job.isWorking {
                ScanningEffect()
            }
        }
        .frame(width: capture.pointSize.width, height: capture.pointSize.height, alignment: .topLeading)
        .clipped()
        .overlay {
            if !capture.isFullScreen {
                Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.18), value: job.items)
        .animation(.easeOut(duration: 0.12), value: job.showOriginal)
        .translationTask(job.appleConfiguration) { session in
            await job.runAppleTranslation(session)
        }
    }
}

struct TranslatedBlock: View {
    let item: TranslationJob.Item

    var body: some View {
        Text(item.translation ?? "")
            .font(.system(size: item.fontSize, weight: .medium))
            .foregroundStyle(item.foreground.color)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .minimumScaleFactor(0.3)
            .padding(.horizontal, 2)
            .frame(width: item.frame.width, height: item.frame.height, alignment: .leading)
            .background(
                item.background.color,
                in: RoundedRectangle(cornerRadius: min(4, item.frame.height * 0.2), style: .continuous)
            )
            .environment(\.layoutDirection, .rightToLeft)
            .help(item.source)
    }
}

/// A soft band sweeping over the capture while OCR and translation run.
struct ScanningEffect: View {
    @State private var atBottom = false

    var body: some View {
        GeometryReader { geometry in
            let band = max(24, min(160, geometry.size.height * 0.25))
            LinearGradient(
                colors: [.clear, Color.accentColor.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geometry.size.width, height: band)
            .offset(y: atBottom ? geometry.size.height - band / 2 : -band / 2)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                atBottom = true
            }
        }
    }
}

/// Floating capsule under the overlay: status + actions.
struct OverlayToolbar: View {
    @ObservedObject var job: TranslationJob
    let onClose: () -> Void
    let onOpenText: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            status
                .frame(maxWidth: 320, alignment: .leading)

            Divider().frame(height: 18)

            ToolbarButton(
                symbol: job.showOriginal ? "eye.slash" : "eye",
                help: job.showOriginal ? "إظهار الترجمة (مسافة)" : "إظهار النص الأصلي (مسافة)"
            ) { job.showOriginal.toggle() }

            ToolbarButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "نسخ الترجمة (⌘C)") {
                job.copyTranslation()
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
            }
            .disabled(job.progress.done == 0)

            ToolbarButton(symbol: "text.alignright", help: "عرض الترجمة كنص", action: onOpenText)
                .disabled(job.items.isEmpty)

            ToolbarButton(symbol: job.isPinned ? "pin.fill" : "pin", help: "تثبيت الترجمة على الشاشة") {
                job.isPinned.toggle()
            }

            ToolbarButton(symbol: "xmark", help: "إغلاق (Esc)", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .environment(\.layoutDirection, .rightToLeft)
        .fixedSize()
    }

    @ViewBuilder
    private var status: some View {
        switch job.phase {
        case .recognizing:
            Label { Text("جاري قراءة النص…") } icon: { ProgressView().controlSize(.small) }
        case .translating:
            let progress = job.progress
            Label {
                Text(progress.total > 1 ? "جاري الترجمة… \(progress.done)/\(progress.total)" : "جاري الترجمة…")
            } icon: {
                ProgressView().controlSize(.small)
            }
        case .done:
            Label(job.notice ?? "تمت الترجمة — \(job.engineUsed?.shortTitle ?? "")", systemImage: job.notice == nil ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(job.notice == nil ? Color.green : Color.orange)
                .lineLimit(2)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(3)
        }
    }
}

struct ToolbarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
