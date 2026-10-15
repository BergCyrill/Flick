import FlickCore
import Foundation

/// The state the settings window edits. Gesture settings are saved to UserDefaults on every
/// change; launch at login goes straight to macOS.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let updater: Updater?

    @Published var settings: FlickSettings {
        didSet { settings.save(to: defaults) }
    }

    /// Mirrors *Pause gestures* from the menu so the window can show a note. Not saved.
    @Published var isPaused = false

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            loginProblem = LoginItem.set(enabled: launchAtLogin)
            // Flip the switch back if macOS didn't follow.
            launchAtLogin = LoginItem.isEnabled
        }
    }

    /// Mirrors Sparkle's own setting.
    @Published var checksForUpdates: Bool {
        didSet { updater?.automaticallyChecksForUpdates = checksForUpdates }
    }

    /// Shown under the launch-at-login switch instead of its hint.
    @Published private(set) var loginProblem: String?

    init(defaults: UserDefaults = .standard, updater: Updater? = nil) {
        self.defaults = defaults
        self.updater = updater
        settings = FlickSettings(defaults: defaults)
        checksForUpdates = updater?.automaticallyChecksForUpdates ?? false
        launchAtLogin = LoginItem.isEnabled
        loginProblem = LoginItem.problem
    }

    /// Re-reads launch at login, which can change in System Settings while Flick runs.
    func refreshLoginItem() {
        launchAtLogin = LoginItem.isEnabled
        loginProblem = LoginItem.problem
    }
}
