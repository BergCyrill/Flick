import Foundation

/// The update the menu-bar dot and *Update to …* point at: one a check found, or the user
/// postponed with *Remind Me Later*, until they install or skip it. It is also remembered for
/// the next launch, so Flick can check again then instead of waiting for the next scheduled check.
public struct PendingUpdate {
    /// What the user did in Sparkle's update dialog.
    public enum Choice: Sendable {
        case install, skip, later
    }

    static let key = "pendingUpdateVersion"
    private let defaults: UserDefaults

    /// The version to show, or nil when nothing waits in this run of Flick.
    public private(set) var version: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public mutating func found(_ version: String) {
        set(version)
    }

    public mutating func userChose(_ choice: Choice, version: String) {
        set(choice == .later ? version : nil)
    }

    /// True when an update was still waiting when Flick last quit. Forgets it: the check this
    /// prompts finds it again if it is still there.
    public func takeWaitingFromLastLaunch() -> Bool {
        guard defaults.string(forKey: Self.key) != nil else { return false }
        defaults.removeObject(forKey: Self.key)
        return true
    }

    private mutating func set(_ version: String?) {
        self.version = version
        defaults.set(version, forKey: Self.key)
    }
}
