import Foundation

/// Carries the settings over from Flick's first bundle ID: UserDefaults are kept per bundle ID,
/// so without this the move to `io.github.bergcyrill.flick` would reset them.
public enum SettingsMigration {
    /// The bundle ID, and with it the defaults domain, before releases existed.
    public static let oldDomain = "local.personal.flick"
    static let doneKey = "settingsMigratedFromOldDomain"

    /// Copies the settings from `old` to `new`, once. Does nothing when `new` already holds a
    /// setting: the user has changed something since, and that wins.
    public static func run(from old: UserDefaults, to new: UserDefaults) {
        guard !new.bool(forKey: doneKey) else { return }
        new.set(true, forKey: doneKey)
        let keys = FlickSettings.storedKeys
        guard !keys.contains(where: { new.object(forKey: $0) != nil }) else { return }
        for key in keys {
            if let value = old.object(forKey: key) {
                new.set(value, forKey: key)
            }
        }
    }
}
