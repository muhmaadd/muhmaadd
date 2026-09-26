import AppKit
import Carbon.HIToolbox

enum TranslationEngine: String, CaseIterable, Identifiable {
    case apple
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple — على الجهاز وبدون إنترنت"
        case .google: "Google — عبر الإنترنت"
        }
    }

    var shortTitle: String {
        switch self {
        case .apple: "Apple (على الجهاز)"
        case .google: "Google"
        }
    }
}

enum SourceLanguage: String, CaseIterable, Identifiable {
    case english
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "الإنجليزية"
        case .auto: "اكتشاف تلقائي"
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    /// Draw the Arabic text on top of the original, like Google Lens.
    case overlay
    /// Show the translation as text in a floating panel.
    case panel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overlay: "فوق النص الأصلي مباشرة"
        case .panel: "في نافذة نصية"
        }
    }
}

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case optionShift
    case controlOption
    case controlShift

    var id: String { rawValue }

    var symbols: String {
        switch self {
        case .optionShift: "⌥⇧"
        case .controlOption: "⌃⌥"
        case .controlShift: "⌃⇧"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionShift: UInt32(optionKey | shiftKey)
        case .controlOption: UInt32(controlKey | optionKey)
        case .controlShift: UInt32(controlKey | shiftKey)
        }
    }

    var menuModifiers: NSEvent.ModifierFlags {
        switch self {
        case .optionShift: [.option, .shift]
        case .controlOption: [.control, .option]
        case .controlShift: [.control, .shift]
        }
    }
}

/// The three global shortcuts. Letters are physical key positions, so they work
/// the same with the Arabic keyboard layout.
enum HotkeyAction: CaseIterable {
    case region
    case fullScreen
    case selectedText

    var keyCode: UInt32 {
        switch self {
        case .region: UInt32(kVK_ANSI_T)
        case .fullScreen: UInt32(kVK_ANSI_F)
        case .selectedText: UInt32(kVK_ANSI_V)
        }
    }

    var keyEquivalent: String {
        switch self {
        case .region: "t"
        case .fullScreen: "f"
        case .selectedText: "v"
        }
    }

    func label(_ preset: HotkeyPreset) -> String {
        preset.symbols + keyEquivalent.uppercased()
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var engine: TranslationEngine {
        didSet { defaults.set(engine.rawValue, forKey: "engine") }
    }
    @Published var allowOnlineFallback: Bool {
        didSet { defaults.set(allowOnlineFallback, forKey: "allowOnlineFallback") }
    }
    @Published var sourceLanguage: SourceLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: "sourceLanguage") }
    }
    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: "displayMode") }
    }
    @Published var copyAutomatically: Bool {
        didSet { defaults.set(copyAutomatically, forKey: "copyAutomatically") }
    }
    @Published var grabSelectedText: Bool {
        didSet { defaults.set(grabSelectedText, forKey: "grabSelectedText") }
    }
    @Published var hotkeyPreset: HotkeyPreset {
        didSet { defaults.set(hotkeyPreset.rawValue, forKey: "hotkeyPreset") }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    private init() {
        defaults.register(defaults: [
            "allowOnlineFallback": true,
            "copyAutomatically": false,
            "grabSelectedText": true,
        ])
        engine = TranslationEngine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .apple
        allowOnlineFallback = defaults.bool(forKey: "allowOnlineFallback")
        sourceLanguage = SourceLanguage(rawValue: defaults.string(forKey: "sourceLanguage") ?? "") ?? .english
        displayMode = DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .overlay
        copyAutomatically = defaults.bool(forKey: "copyAutomatically")
        grabSelectedText = defaults.bool(forKey: "grabSelectedText")
        hotkeyPreset = HotkeyPreset(rawValue: defaults.string(forKey: "hotkeyPreset") ?? "") ?? .optionShift
    }
}
