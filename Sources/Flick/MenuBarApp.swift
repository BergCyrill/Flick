import AppKit
import FlickCore

/// Menu-bar item, Accessibility handling and wiring of the whole app.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    /// Seconds an Accessibility call may block. Set on the system-wide element it applies to
    /// every AX call Flick makes, so a hung app can't stall the event tap (and with it all
    /// scrolling) for the default ~6 s.
    private static let accessibilityTimeout: Float = 0.25

    private var statusItem: NSStatusItem?
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause gestures", action: nil, keyEquivalent: "")
    private var recognizer: GestureRecognizer?
    private var tap: EventTap?
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.accessibilityTimeout)
        let controller = FlickController(windows: WindowMover(), screens: ScreenAdapter(), preview: PreviewOverlay())
        // Updates are handled after the tap callback returns: moving a window takes several
        // Accessibility round-trips, and the swallow decision doesn't depend on them.
        let recognizer = GestureRecognizer(probe: TitlebarHitTester()) { update in
            DispatchQueue.main.async { controller.handle(update) }
        }
        self.recognizer = recognizer
        tap = EventTap(recognizer: recognizer)
        buildMenu()

        if Accessibility.isTrusted(prompt: true) {
            startTap()
        } else {
            waitForTrust()
        }
        refreshMenu()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.icon()
        item.button?.toolTip = "Flick"

        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(accessLine)
        menu.addItem(.separator())
        pauseItem.target = self
        pauseItem.action = #selector(togglePause)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Flick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func refreshMenu() {
        let trusted = tap?.isRunning ?? false
        let paused = recognizer?.isPaused ?? false
        if !trusted {
            statusLine.title = "Waiting for Accessibility access"
        } else {
            statusLine.title = paused ? "Flick is paused" : "Flick is active"
        }
        if trusted {
            accessLine.title = "Accessibility access granted"
            accessLine.isEnabled = false
            accessLine.action = nil
        } else {
            accessLine.title = "Grant Accessibility Access…"
            accessLine.isEnabled = true
            accessLine.target = self
            accessLine.action = #selector(openAccessibilitySettings)
        }
        pauseItem.state = paused ? .on : .off
        pauseItem.isEnabled = trusted
    }

    private func startTap() {
        _ = tap?.start()
        refreshMenu()
    }

    private func waitForTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
    }

    private func checkTrust() {
        guard Accessibility.isTrusted(prompt: false) else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        startTap()
    }

    @objc private func togglePause() {
        recognizer?.isPaused.toggle()
        refreshMenu()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    /// The menu-bar glyph from the design drawing, as a template image.
    private static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 12), flipped: true) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 2, y: 10))
            path.line(to: NSPoint(x: 8, y: 4))
            path.move(to: NSPoint(x: 6, y: 11))
            path.line(to: NSPoint(x: 13, y: 4))
            path.move(to: NSPoint(x: 10, y: 2))
            path.line(to: NSPoint(x: 14, y: 2))
            path.line(to: NSPoint(x: 14, y: 6))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
