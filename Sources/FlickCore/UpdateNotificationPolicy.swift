import Foundation

/// Notifies about each update version once: an update the user leaves waiting is found again
/// after every relaunch, and only the menu-bar dot should keep pointing at it then.
public struct UpdateNotificationPolicy {
    static let key = "lastNotifiedUpdateVersion"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True the first time it sees `version` (Sparkle's build number), and records it.
    public func shouldNotify(about version: String) -> Bool {
        guard defaults.string(forKey: Self.key) != version else { return false }
        defaults.set(version, forKey: Self.key)
        return true
    }
}
