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
    private weak var previousApp: NSRunningApplication?

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
        // Remember who was in front so we can paste back into them.
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        positionPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func openAccessibilitySettings() {
        // Re-trigger the system prompt and open the relevant settings pane.
        _ = Paster.hasAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Paste an item into the previously-focused application.
    private func paste(_ item: ClipItem) {
        Paster.copyToPasteboard(item, store: store, monitor: monitor)
        hide()

        let canSendKeys = Paster.hasAccessibilityPermission(prompt: false)
        let prev = previousApp

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            prev?.activate()
            if canSendKeys {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    Paster.simulatePaste()
                }
            }
        }
    }

    // MARK: - Panel construction

    private func makePanel() -> KeyablePanel {
        let root = HistoryView(
            store: store,
            onPaste: { [weak self] item in self?.paste(item) },
            onClose: { [weak self] in self?.hide() },
            onQuit: { NSApp.terminate(nil) },
            onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
            checkTrusted: { Paster.hasAccessibilityPermission(prompt: false) }
        )
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.wantsLayer = true

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = true
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
