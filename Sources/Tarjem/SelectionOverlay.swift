import AppKit

/// Dims every screen and lets the user drag a rectangle over the text to
/// translate. Space / Return / F picks the whole screen, Esc cancels.
@MainActor
final class SelectionOverlay {
    enum Result {
        /// `rect` is in the screen's own coordinates (points, origin top-left).
        case region(screen: NSScreen, rect: CGRect)
        case fullScreen(screen: NSScreen)
    }

    private var windows: [SelectionWindow] = []
    private var completion: ((Result?) -> Void)?
    private var keyMonitor: Any?

    var isActive: Bool { completion != nil }

    func begin(_ completion: @escaping (Result?) -> Void) {
        guard !isActive else { return }
        self.completion = completion

        let mouseScreen = NSScreen.underMouse
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onSelect = { [weak self] rect in
                self?.finish(.region(screen: screen, rect: rect))
            }
            window.contentView = view
            windows.append(window)
            if screen == mouseScreen {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            } else {
                window.orderFrontRegardless()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        NSCursor.crosshair.push()
    }

    func cancel() {
        finish(nil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53: // Esc
            finish(nil)
            return true
        case 49, 36, 76, 3: // Space, Return, Enter, F
            if let screen = NSScreen.underMouse { finish(.fullScreen(screen: screen)) }
            return true
        default:
            return false
        }
    }

    private func finish(_ result: Result?) {
        guard let completion else { return }
        self.completion = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion(result)
    }
}

final class SelectionWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        ).intersection(bounds)
        return rect.isNull ? nil : rect
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let rect = selection?.integral
        start = nil
        current = nil
        needsDisplay = true
        if let rect, rect.width >= 8, rect.height >= 8 {
            onSelect?(rect)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let rect = selection, rect.width > 0, rect.height > 0 else {
            drawHint()
            return
        }

        NSColor.clear.setFill()
        rect.fill(using: .copy)

        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        rect.fill(using: .sourceOver)

        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1.5
        NSColor.white.setStroke()
        border.stroke()

        drawBadge(
            "\(Int(rect.width)) × \(Int(rect.height))",
            at: CGPoint(x: rect.minX, y: rect.maxY + 6),
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        )
    }

    private func drawHint() {
        let text = "اسحب فوق النص المراد ترجمته   •   مسافة: الشاشة كاملة   •   Esc: إلغاء"
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        drawBadge(text, at: CGPoint(x: bounds.midX - size.width / 2 - 12, y: 60), font: font)
    }

    private func drawBadge(_ text: String, at origin: CGPoint, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        var badge = CGRect(x: origin.x, y: origin.y, width: size.width + 24, height: size.height + 12)
        badge.origin.x = min(max(badge.minX, 8), bounds.maxX - badge.width - 8)
        badge.origin.y = min(badge.minY, bounds.maxY - badge.height - 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: badge.minX + 12, y: badge.minY + 6), withAttributes: attributes)
    }
}
