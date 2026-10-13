import AppKit
import FlickCore

/// Menu-bar item and Accessibility handling.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private var statusItem: NSStatusItem?
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var trusted = false
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        trusted = Accessibility.isTrusted(prompt: true)
        if !trusted {
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
        menu.addItem(
            NSMenuItem(title: "Quit Flick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func refreshMenu() {
        statusLine.title = trusted ? "Flick is active" : "Waiting for Accessibility access"
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
        trusted = true
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
