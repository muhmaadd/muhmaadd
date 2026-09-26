import AppKit
import Combine
import SwiftUI

/// Places the translated snapshot exactly over the captured area, plus a small
/// toolbar. Closes on Esc, on ✕, or when the user clicks elsewhere (unless pinned).
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    let job: TranslationJob
    var onClose: ((OverlayController) -> Void)?
    var onOpenText: ((TranslationJob) -> Void)?

    private let capture: CapturedImage
    private let window: OverlayPanel
    private let toolbar: OverlayPanel
    private let toolbarHost: NSHostingView<OverlayToolbar>
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var isClosed = false

    init(job: TranslationJob, capture: CapturedImage) {
        self.job = job
        self.capture = capture
        window = OverlayPanel(frame: capture.screenFrame, canBecomeKey: true)
        toolbar = OverlayPanel(frame: .zero, canBecomeKey: false)
        toolbarHost = NSHostingView(rootView: OverlayToolbar(job: job, onClose: {}, onOpenText: {}))
        super.init()

        window.contentView = NSHostingView(rootView: OverlayView(job: job, capture: capture))
        window.hasShadow = !capture.isFullScreen
        window.delegate = self

        toolbarHost.rootView = OverlayToolbar(
            job: job,
            onClose: { [weak self] in self?.close() },
            onOpenText: { [weak self] in self?.openText() }
        )
        toolbar.contentView = toolbarHost
        toolbar.hasShadow = true
    }

    var isPinned: Bool { job.isPinned }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.addChildWindow(toolbar, ordered: .above)
        layoutToolbar()
        toolbar.orderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }

        // The toolbar changes width with its status text.
        job.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layoutToolbar() }
            .store(in: &cancellables)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        cancellables.removeAll()
        window.removeChildWindow(toolbar)
        toolbar.orderOut(nil)
        window.orderOut(nil)
        window.delegate = nil
        onClose?(self)
    }

    private func openText() {
        onOpenText?(job)
        close()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === window || event.window === toolbar else { return false }
        switch Int(event.keyCode) {
        case 53: // Esc
            close()
            return true
        case 49: // Space
            job.showOriginal.toggle()
            return true
        case 8 where event.modifierFlags.contains(.command): // ⌘C
            job.copyTranslation()
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another app dismisses the overlay, like a popover.
        if !job.isPinned { close() }
    }

    private func layoutToolbar() {
        guard !isClosed else { return }
        toolbarHost.layoutSubtreeIfNeeded()
        let size = toolbarHost.fittingSize
        let frame = capture.screenFrame
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }?.frame ?? frame
        let gap: CGFloat = 8

        var origin = CGPoint(x: frame.midX - size.width / 2, y: 0)
        if capture.isFullScreen {
            origin.y = frame.minY + 48
        } else if frame.minY - gap - size.height >= screen.minY + 4 {
            origin.y = frame.minY - gap - size.height
        } else if frame.maxY + gap + size.height <= screen.maxY - 4 {
            origin.y = frame.maxY + gap
        } else {
            origin.y = frame.minY + gap
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        toolbar.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

final class OverlayPanel: NSPanel {
    private let allowsKey: Bool

    init(frame: CGRect, canBecomeKey: Bool) {
        allowsKey = canBecomeKey
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = !canBecomeKey
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
