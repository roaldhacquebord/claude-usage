import AppKit

@main
@MainActor
enum ClaudeUsageMain {
    static func main() {
        let app = NSApplication.shared
        // Info.plist's LSUIElement does this for the bundled app; this also covers running the bare binary.
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
