import AppKit
import SwiftUI

/// The settings window from the design drawing. Created on first use and reused.
@MainActor
final class SettingsWindow {
    private let store: SettingsStore
    private var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        store.refreshLoginItem()
        let window = self.window ?? makeWindow()
        self.window = window
        // Flick has no Dock icon, so nothing else brings the window to the front.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
        window.title = "Flick Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            if store.isPaused {
                Section {
                    Label(
                        "Gestures are paused from the menu bar. Your switches keep their values.",
                        systemImage: "pause.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            Section("Gestures") {
                Toggle(isOn: $store.settings.swipeToSnap) {
                    Self.label("Swipe on titlebar to snap", hint: "Two fingers on a titlebar: halves and quarters.")
                }
                Toggle(isOn: $store.settings.pinchToFillRestore) {
                    Self.label(
                        "Pinch on titlebar to fill and restore", hint: "Pinch out fills the screen, pinch in restores.")
                }
                Toggle(isOn: $store.settings.scrollWhileDragging) {
                    Self.label(
                        "Scroll while dragging to fill and restore",
                        hint: "Drag a window by its titlebar, scroll away to fill, towards you to restore.")
                }
            }
            Section("Feedback") {
                Toggle(isOn: $store.settings.livePreview) {
                    Self.label(
                        "Show live preview",
                        hint: "Blue outline of the target while you gesture. Off: the window just moves on release.")
                }
            }
            Section("General") {
                Toggle(isOn: $store.launchAtLogin) {
                    Self.label(
                        "Launch at login",
                        hint: store.loginProblem ?? "Shows the state from System Settings → General → Login Items.",
                        isProblem: store.loginProblem != nil)
                }
                if store.loginProblem != nil {
                    Button("Open Login Items…") { LoginItem.openSystemSettings() }
                }
            }
            Section {
                Text("Fullscreen windows are always left alone. Changes apply from the next gesture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: 480, height: 560)
    }

    private static func label(_ title: String, hint: String, isProblem: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(hint)
                .font(.caption)
                .foregroundStyle(isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }
}
