import AppKit

@main
struct BboxApp {
    // Held for the lifetime of the app (NSApplication.delegate is weak).
    @MainActor static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared

        // Offscreen preview render mode: `Bbox --render /path/to/out.png`.
        if let idx = CommandLine.arguments.firstIndex(of: "--render"),
           idx + 1 < CommandLine.arguments.count {
            app.setActivationPolicy(.accessory)
            let real = CommandLine.arguments.contains("--real")
            PreviewRenderer.render(to: CommandLine.arguments[idx + 1], useRealStore: real)
            return
        }

        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
