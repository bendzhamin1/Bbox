import AppKit
import SwiftUI

/// A borderless panel that can still become key so the search field accepts typing.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Manages the floating history panel and coordinates paste-back into the
/// app that was frontmost before the panel opened.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private var panel: KeyablePanel?

    static let panelWidth: CGFloat = 300
    static let panelHeight: CGFloat = 420

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        // Grab whatever was just copied before showing the list.
        monitor.captureNow()

        let panel = panel ?? makePanel()
        self.panel = panel

        // Rebuild the SwiftUI content each time so the list always reflects the
        // current history (a reused off-screen hosting view can show a stale
        // snapshot).
        panel.contentView = makeHostingView()

        positionPanel(panel)
        // Do NOT activate the app: a non-activating panel becomes key for typing
        // while the app the user was in stays active, so its text field keeps its
        // insertion point and Cmd+V lands there after we close.
        // orderFrontRegardless brings it visually above other apps' windows even
        // though our app is not the active one; makeKey lets it receive keys.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Paste an item into the previously-focused application.
    private func paste(_ item: ClipItem) {
        Paster.copyToPasteboard(item, store: store, monitor: monitor)
        store.moveToTop(item)   // the just-used item becomes the most recent

        let canSendKeys = Paster.hasAccessibilityPermission(prompt: false)

        // Closing the panel returns key focus to the app the user was in (it was
        // never deactivated), so its text field is focused again and Cmd+V lands.
        hide()

        guard canSendKeys else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Paster.simulatePaste()
        }
    }

    // MARK: - Panel construction

    private func makeHostingView() -> NSHostingView<AnyView> {
        let root = HistoryView(
            store: store,
            onPaste: { [weak self] item in self?.paste(item) },
            onClose: { [weak self] in self?.hide() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.wantsLayer = true
        return hosting
    }

    private func makePanel() -> KeyablePanel {
        let hosting = makeHostingView()

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        // Must be false: the app is never activated, so a true value would make
        // macOS hide the panel immediately (it would still grab keys, blocking
        // typing in the app underneath). We close it ourselves on Esc/resign key.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Place the panel at the saved position, or bottom-left of the screen by default.
    /// The saved position is remembered across launches (and reboots) via UserDefaults.
    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        let margin: CGFloat = 16

        var origin: NSPoint
        if let saved = savedOrigin() {
            origin = saved
        } else {
            // Default: bottom-left corner.
            origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        }

        // Keep it on-screen.
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Saved position

    private static let originXKey = "Bbox.panelOriginX"
    private static let originYKey = "Bbox.panelOriginY"

    private func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.originXKey) != nil,
              defaults.object(forKey: Self.originYKey) != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: Self.originXKey),
                       y: defaults.double(forKey: Self.originYKey))
    }

    private func saveOrigin(_ origin: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x), forKey: Self.originXKey)
        defaults.set(Double(origin.y), forKey: Self.originYKey)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        // Remember where the user dragged the panel.
        guard let window = notification.object as? NSWindow, window === panel else { return }
        saveOrigin(window.frame.origin)
    }
}
