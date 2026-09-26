import AppKit
import ServiceManagement
import SwiftUI
import Translation

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "إعدادات ترجِم"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var languageStatus: LanguageAvailability.Status?
    @State private var downloadConfiguration: TranslationSession.Configuration?
    @State private var downloadError: String?
    @State private var hasScreenPermission = ScreenCapture.hasPermission
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ترجِم — ترجمة الشاشة من الإنجليزية إلى العربية").font(.headline)
                    Text("اضغط أيقونة ترجِم في شريط القوائم، ثم حدّد منطقة من الشاشة أو اختر الشاشة كاملة، فتظهر الترجمة فوق النص الأصلي مباشرة.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("الأذونات") {
                permissionRow(
                    title: "تسجيل الشاشة",
                    detail: "ضروري لقراءة النص من الشاشة.",
                    granted: hasScreenPermission
                ) {
                    ScreenCapture.requestPermission()
                    SystemSettings.openScreenRecordingPrivacy()
                }
                permissionRow(
                    title: "تسهيلات الاستخدام (اختياري)",
                    detail: "لترجمة النص المحدّد مباشرة دون نسخه يدوياً.",
                    granted: hasAccessibility
                ) {
                    SelectedText.requestAccessibility()
                    SystemSettings.openAccessibilityPrivacy()
                }
                Text("بعد منح إذن تسجيل الشاشة قد تحتاج إلى إعادة تشغيل التطبيق.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("الترجمة") {
                Picker("محرك الترجمة", selection: $settings.engine) {
                    ForEach(TranslationEngine.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)

                if settings.engine == .apple {
                    appleLanguageRow
                }

                Toggle("استخدام Google تلقائياً عند تعذّر ترجمة Apple", isOn: $settings.allowOnlineFallback)
                    .disabled(settings.engine == .google)

                Picker("لغة النص الأصلي", selection: $settings.sourceLanguage) {
                    ForEach(SourceLanguage.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("العرض") {
                Picker("طريقة عرض ترجمة الشاشة", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("نسخ الترجمة إلى الحافظة تلقائياً", isOn: $settings.copyAutomatically)
                Toggle("اختصار النص يترجم النص المحدّد (وإلا فالمنسوخ)", isOn: $settings.grabSelectedText)
            }

            Section("اختصارات لوحة المفاتيح") {
                Picker("مفاتيح التعديل", selection: $settings.hotkeyPreset) {
                    ForEach(HotkeyPreset.allCases) { Text($0.symbols).tag($0) }
                }
                .pickerStyle(.segmented)
                shortcutRow("ترجمة جزء من الشاشة", .region)
                shortcutRow("ترجمة الشاشة كاملة", .fullScreen)
                shortcutRow("ترجمة النص المحدّد أو المنسوخ", .selectedText)
            }

            Section("النظام") {
                Toggle("التشغيل عند بدء تسجيل الدخول", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .environment(\.layoutDirection, .rightToLeft)
        .task { await refreshLanguageStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenPermission = ScreenCapture.hasPermission
            hasAccessibility = AXIsProcessTrusted()
        }
        .translationTask(downloadConfiguration) { session in
            do {
                try await session.prepareTranslation()
                downloadError = nil
            } catch {
                downloadError = error.localizedDescription
            }
            await refreshLanguageStatus()
        }
    }

    @ViewBuilder
    private var appleLanguageRow: some View {
        HStack {
            switch languageStatus {
            case .installed:
                Label("العربية منزّلة وجاهزة للعمل دون إنترنت", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .supported:
                Label("حزمة العربية غير منزّلة بعد", systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("تنزيل") {
                    Task {
                        let target = await AppleTranslation.arabic()
                        if downloadConfiguration == nil {
                            downloadConfiguration = .init(source: AppleTranslation.english, target: target)
                        } else {
                            downloadConfiguration?.invalidate()
                        }
                    }
                }
            case .unsupported:
                Label("ترجمة Apple لا تدعم هذا الزوج من اللغات على جهازك", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case nil:
                ProgressView().controlSize(.small)
                Text("جاري التحقق من حزمة العربية…").foregroundStyle(.secondary)
            @unknown default:
                EmptyView()
            }
        }
        .font(.callout)
        if let downloadError {
            Text(downloadError).font(.caption).foregroundStyle(.red)
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, grant: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("ممنوح", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("منح الإذن", action: grant)
            }
        }
    }

    private func shortcutRow(_ title: String, _ action: HotkeyAction) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(action.label(settings.hotkeyPreset))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func refreshLanguageStatus() async {
        languageStatus = await AppleTranslation.status(source: AppleTranslation.english, sample: "")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "تعذّر تغيير الإعداد: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
