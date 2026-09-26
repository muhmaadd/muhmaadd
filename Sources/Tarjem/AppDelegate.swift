import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let selection = SelectionOverlay()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var overlays: [OverlayController] = []
    private var panels: [TextPanelController] = []
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotKeys()
        settings.$hotkeyPreset
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        if !settings.hasCompletedOnboarding {
            settings.hasCompletedOnboarding = true
            settingsWindow.show()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "ترجِم")
            ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "ترجِم")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "ترجِم — ترجمة الشاشة إلى العربية"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt every time it opens, so it always reflects the current settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let preset = settings.hotkeyPreset

        menu.addItem(actionItem("ترجمة جزء من الشاشة…", symbol: "rectangle.dashed", action: #selector(translateRegion),
                                key: HotkeyAction.region.keyEquivalent, modifiers: preset.menuModifiers))
        menu.addItem(actionItem("ترجمة الشاشة كاملة", symbol: "macwindow", action: #selector(translateFullScreen),
                                key: HotkeyAction.fullScreen.keyEquivalent, modifiers: preset.menuModifiers))
        menu.addItem(actionItem("ترجمة النص المحدّد أو المنسوخ", symbol: "doc.on.clipboard", action: #selector(translateText),
                                key: HotkeyAction.selectedText.keyEquivalent, modifiers: preset.menuModifiers))
        menu.addItem(.separator())

        let engineMenu = NSMenu()
        for engine in TranslationEngine.allCases {
            let item = NSMenuItem(title: engine.title, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = settings.engine == engine ? .on : .off
            engineMenu.addItem(item)
        }
        menu.addItem(submenuItem("محرك الترجمة", symbol: "cpu", submenu: engineMenu))

        let displayMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.displayMode == mode ? .on : .off
            displayMenu.addItem(item)
        }
        menu.addItem(submenuItem("طريقة العرض", symbol: "text.below.photo", submenu: displayMenu))

        menu.addItem(.separator())
        menu.addItem(actionItem("الإعدادات…", symbol: "gearshape", action: #selector(openSettings), key: ",", modifiers: .command))
        menu.addItem(actionItem("إنهاء ترجِم", symbol: nil, action: #selector(quit), key: "q", modifiers: .command))
    }

    private func actionItem(_ title: String, symbol: String?, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func submenuItem(_ title: String, symbol: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    // MARK: - Shortcuts

    private func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        let modifiers = settings.hotkeyPreset.carbonModifiers
        center.register(keyCode: HotkeyAction.region.keyCode, modifiers: modifiers) { [weak self] in self?.translateRegion() }
        center.register(keyCode: HotkeyAction.fullScreen.keyCode, modifiers: modifiers) { [weak self] in self?.translateFullScreen() }
        center.register(keyCode: HotkeyAction.selectedText.keyCode, modifiers: modifiers) { [weak self] in self?.translateText() }
    }

    // MARK: - Actions

    @objc func translateRegion() {
        guard !selection.isActive, ensureScreenPermission() else { return }
        closeUnpinnedOverlays()
        Task {
            // Let the status menu finish closing before dimming the screen.
            try? await Task.sleep(for: .milliseconds(50))
            selection.begin { [weak self] result in
                switch result {
                case .region(let screen, let rect): self?.capture(screen: screen, rect: rect)
                case .fullScreen(let screen): self?.capture(screen: screen, rect: nil)
                case nil: break
                }
            }
        }
    }

    @objc func translateFullScreen() {
        if selection.isActive { selection.cancel() }
        guard ensureScreenPermission(), let screen = NSScreen.underMouse else { return }
        closeUnpinnedOverlays()
        capture(screen: screen, rect: nil)
    }

    @objc func translateText() {
        Task {
            var text: String?
            if settings.grabSelectedText {
                if SelectedText.canGrab {
                    text = await SelectedText.grab()
                } else if !UserDefaults.standard.bool(forKey: "askedAccessibility") {
                    UserDefaults.standard.set(true, forKey: "askedAccessibility")
                    SelectedText.requestAccessibility()
                }
            }
            if text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                text = NSPasteboard.general.string(forType: .string)
            }
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                showAlert(
                    "لا يوجد نص لترجمته",
                    "حدّد نصاً في أي تطبيق أو انسخه (⌘C)، ثم اختر «ترجمة النص المحدّد أو المنسوخ»."
                )
                return
            }
            let job = TranslationJob(text: text)
            showTextPanel(for: job)
            job.start()
        }
    }

    @objc func selectEngine(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let engine = TranslationEngine(rawValue: raw) {
            settings.engine = engine
        }
    }

    @objc func selectDisplayMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) {
            settings.displayMode = mode
        }
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Capture → translate

    private func capture(screen: NSScreen, rect: CGRect?) {
        Task {
            do {
                let captured = try await ScreenCapture.capture(screen: screen, rect: rect)
                present(TranslationJob(capture: captured), capture: captured)
            } catch CaptureError.permissionDenied {
                showScreenPermissionAlert()
            } catch {
                if !ScreenCapture.hasPermission {
                    showScreenPermissionAlert()
                } else {
                    showAlert("تعذّر التقاط الشاشة", error.localizedDescription)
                }
            }
        }
    }

    private func present(_ job: TranslationJob, capture: CapturedImage) {
        switch settings.displayMode {
        case .overlay:
            let overlay = OverlayController(job: job, capture: capture)
            overlay.onClose = { [weak self] controller in
                self?.overlays.removeAll { $0 === controller }
            }
            overlay.onOpenText = { [weak self] job in
                self?.showTextPanel(for: job)
            }
            overlays.append(overlay)
            overlay.show()
        case .panel:
            showTextPanel(for: job)
        }
        job.start()
    }

    private func showTextPanel(for job: TranslationJob) {
        if let existing = panels.first(where: { $0.job === job }) {
            existing.show()
            return
        }
        let panel = TextPanelController(job: job)
        panel.onClose = { [weak self] controller in
            self?.panels.removeAll { $0 === controller }
        }
        panels.append(panel)
        panel.show()
    }

    private func closeUnpinnedOverlays() {
        overlays.filter { !$0.isPinned }.forEach { $0.close() }
    }

    // MARK: - Permissions & alerts

    private func ensureScreenPermission() -> Bool {
        if ScreenCapture.hasPermission { return true }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "askedScreenRecording") {
            // First time: let macOS show its own prompt.
            defaults.set(true, forKey: "askedScreenRecording")
            if ScreenCapture.requestPermission() { return true }
            return false
        }
        showScreenPermissionAlert()
        return false
    }

    private func showScreenPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "يحتاج ترجِم إلى إذن تسجيل الشاشة"
        alert.informativeText = """
        لقراءة النص من الشاشة افتح: إعدادات النظام ← الخصوصية والأمان ← تسجيل الشاشة وصوت النظام، \
        ثم فعّل «ترجِم». بعد منح الإذن أعد تشغيل التطبيق.
        """
        alert.addButton(withTitle: "فتح إعدادات النظام")
        alert.addButton(withTitle: "إعادة تشغيل ترجِم")
        alert.addButton(withTitle: "لاحقاً")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            SystemSettings.openScreenRecordingPrivacy()
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
