import AppKit
import SwiftUI

/// Renders the history panel offscreen to a PNG. Used only via `--render <path>`
/// for design previews; not part of the shipping runtime path.
@MainActor
enum PreviewRenderer {
    static func render(to path: String, useRealStore: Bool = false) {
        let store: HistoryStore
        if useRealStore {
            store = HistoryStore()          // reads the real on-disk history
        } else {
            store = HistoryStore(ephemeral: true)
            store.seedPreview()
        }

        let w = PanelController.panelWidth
        let h = PanelController.panelHeight

        // A backdrop so the translucent glass reads in a static image.
        let content = ZStack {
            LinearGradient(colors: [
                Color(red: 0.18, green: 0.20, blue: 0.28),
                Color(red: 0.28, green: 0.22, blue: 0.34)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            HistoryView(store: store,
                        onPaste: { _ in },
                        onClose: {},
                        onQuit: {})
                .padding(20)
        }
        .frame(width: w + 40, height: h + 40)

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(x: 0, y: 0, width: w + 40, height: h + 40)

        // Back the view with a real (offscreen) window so materials render.
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFrontRegardless()

        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered -> \(path)")
        exit(0)
    }
}
