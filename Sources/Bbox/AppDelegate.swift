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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy may run: two instances would poll and write the same
        // history file at once, producing wrong/garbled entries and odd ordering.
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        // No Dock icon and no menu bar icon. The app is invisible and is driven
        // entirely by the Option+V hotkey. Quitting is done from inside the panel.
        NSApp.setActivationPolicy(.accessory)
        setupHiddenMenu()

        monitor = ClipboardMonitor(store: store)
        panelController = PanelController(store: store, monitor: monitor)
        monitor.start()

        // Global hotkey: Option+V toggles the panel.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(optionKey)) { [weak self] in
            self?.panelController.toggle()
        }

        // Start automatically at login.
        enableLaunchAtLogin()

        // Ask for Accessibility permission on first run so paste-back works.
        if !Paster.hasAccessibilityPermission(prompt: false) {
            _ = Paster.hasAccessibilityPermission(prompt: true)
        }
    }

    /// A minimal main menu that is never shown (accessory apps have no menu bar),
    /// but lets Cmd+Q quit while the panel is focused.
    private func setupHiddenMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Bbox", action: #selector(quit), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
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

    @objc private func quit() { NSApp.terminate(nil) }
}
