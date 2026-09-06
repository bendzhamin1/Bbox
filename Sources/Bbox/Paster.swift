import Foundation
import AppKit

/// Writes a history item back to the pasteboard and (optionally) simulates
/// Cmd+V into the previously-focused application.
@MainActor
enum Paster {
    /// Put an item on the pasteboard. Returns true on success.
    @discardableResult
    static func copyToPasteboard(_ item: ClipItem, store: HistoryStore, monitor: ClipboardMonitor) -> Bool {
        let pb = NSPasteboard.general
        monitor.suppressNextCapture()
        pb.clearContents()

        switch item.kind {
        case .text:
            return pb.setString(item.payload, forType: .string)
        case .image:
            guard let data = try? Data(contentsOf: store.imageURL(for: item)) else { return false }
            // Offer both PNG and TIFF so any target app can accept the image.
            pb.setData(data, forType: .png)
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            return true
        }
    }

    /// Simulate a Cmd+V keystroke. Requires Accessibility permission.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // 'v'

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Whether the app is trusted for Accessibility (needed to send keystrokes).
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
