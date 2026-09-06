import Foundation
import AppKit

/// Polls the general pasteboard and forwards new content to the history store.
@MainActor
final class ClipboardMonitor {
    private let store: HistoryStore
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// When we write to the pasteboard ourselves (paste-back), we bump this so
    /// the monitor does not re-capture our own write as a new clip.
    private var ignoreNextChangeCount: Int?

    init(store: HistoryStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            // The timer is added to the main run loop, so this fires on the main
            // thread; assume the main actor instead of hopping through a Task
            // (which older Swift rejects for capturing self concurrently).
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Capture the current clipboard immediately (called when the panel opens so
    /// a copy made a split second earlier is already in the list).
    func captureNow() {
        poll()
    }

    /// Call before programmatically setting the pasteboard so the resulting
    /// change is not recorded again.
    func suppressNextCapture() {
        // The changeCount after our write will be current + 1.
        ignoreNextChangeCount = pasteboard.changeCount + 1
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if let ignore = ignoreNextChangeCount, ignore == current {
            ignoreNextChangeCount = nil
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // Prefer real text; fall back to images.
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addText(string, sourceApp: sourceApp)
            return
        }

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let image = NSImage(data: data) {
            store.addImage(image, sourceApp: sourceApp)
        }
    }
}
