import AppKit
import FlickCore

// Before anything reads the settings: carry them over from the old bundle ID, once.
if let old = UserDefaults(suiteName: SettingsMigration.oldDomain) {
    SettingsMigration.run(from: old, to: .standard)
}

let app = NSApplication.shared
let delegate = MenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
