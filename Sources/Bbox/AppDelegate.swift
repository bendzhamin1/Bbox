import AppKit
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HistoryStore()
    private var monitor: ClipboardMonitor!
    private var panelController: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy may run: two instances would poll and write the same
        // history file at once, producing wrong/garbled entries and odd ordering.
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        // Menu bar only — no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        monitor = ClipboardMonitor(store: store)
        panelController = PanelController(store: store, monitor: monitor)
        monitor.start()

        setupStatusItem()

        // Global hotkey: Option+V toggles the panel.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(optionKey)) { [weak self] in
            self?.panelController.toggle()
        }

        // "Install and forget": start automatically at login.
        enableLaunchAtLogin()

        // Ask for Accessibility permission on first run so paste-back works.
        if !Paster.hasAccessibilityPermission(prompt: false) {
            _ = Paster.hasAccessibilityPermission(prompt: true)
        }
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        return !others.isEmpty
    }

    private func enableLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Bbox: launch-at-login registration failed: \(error)")
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Bbox")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть буфер  (⌥V)",
                     action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(.separator())

        let accessibilityOK = Paster.hasAccessibilityPermission(prompt: false)
        let permItem = NSMenuItem(
            title: accessibilityOK ? "Доступ к вставке: включён" : "Включить авто-вставку…",
            action: accessibilityOK ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        menu.addItem(permItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // reset so left-click toggles the panel next time
    }

    @objc private func openPanel() { panelController.show() }

    @objc private func openAccessibilitySettings() {
        _ = Paster.hasAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
