import AppKit
import Carbon.HIToolbox

/// Gets the text the user has selected in the frontmost app by sending ⌘C,
/// then restores the clipboard. Needs the Accessibility permission; without it
/// Tarjem falls back to whatever is already on the clipboard.
enum SelectedText {
    static var canGrab: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func grab() async -> String? {
        guard canGrab else { return nil }

        // Wait for the shortcut's modifier keys to be released so the target app
        // sees a plain ⌘C, not ⌥⇧⌘C.
        let modifiers: CGEventFlags = [.maskAlternate, .maskShift, .maskControl, .maskCommand]
        var waited = 0
        while waited < 40, !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try? await Task.sleep(for: .milliseconds(15))
            waited += 1
        }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        let changeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != changeCount {
                text = pasteboard.string(forType: .string)
                break
            }
        }

        // Put back what the user had on the clipboard.
        if pasteboard.changeCount != changeCount, !saved.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
        return text
    }
}
