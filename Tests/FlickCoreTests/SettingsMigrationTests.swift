import Foundation
import Testing

@testable import FlickCore

@Suite struct SettingsMigrationTests {
    /// Runs `body` with two private defaults domains, old and new, and removes them afterwards.
    func withDomains(_ body: (_ old: UserDefaults, _ new: UserDefaults) -> Void) {
        let names = [UUID(), UUID()].map { "io.github.bergcyrill.flick.tests.\($0.uuidString)" }
        let old = UserDefaults(suiteName: names[0])!
        let new = UserDefaults(suiteName: names[1])!
        defer {
            old.removePersistentDomain(forName: names[0])
            new.removePersistentDomain(forName: names[1])
        }
        body(old, new)
    }

    @Test func copiesTheSettingsWhenTheNewDomainIsEmpty() {
        withDomains { old, new in
            var settings = FlickSettings()
            settings.livePreview = false
            settings.scrollButton = .right
            settings.save(to: old)
            SettingsMigration.run(from: old, to: new)
            #expect(FlickSettings(defaults: new) == settings)
        }
    }

    @Test func carriesTheOldSwitchOver() {
        withDomains { old, new in
            old.set(false, forKey: "scrollWhileDragging")
            SettingsMigration.run(from: old, to: new)
            #expect(FlickSettings(defaults: new).scrollButton == .off)
        }
    }

    @Test func neverOverwritesSettingsInTheNewDomain() {
        withDomains { old, new in
            old.set(false, forKey: "livePreview")
            old.set(false, forKey: "swipeToSnap")
            new.set(true, forKey: "livePreview")
            SettingsMigration.run(from: old, to: new)
            #expect(new.object(forKey: "livePreview") as? Bool == true)
            #expect(new.object(forKey: "swipeToSnap") == nil)
        }
    }

    @Test func runsOnlyOnce() {
        withDomains { old, new in
            SettingsMigration.run(from: old, to: new)
            old.set(false, forKey: "livePreview")
            SettingsMigration.run(from: old, to: new)
            #expect(new.object(forKey: "livePreview") == nil)
        }
    }

    @Test func copiesNothingWhenTheOldDomainIsEmpty() {
        withDomains { old, new in
            SettingsMigration.run(from: old, to: new)
            #expect(FlickSettings.storedKeys.allSatisfy { new.object(forKey: $0) == nil })
        }
    }

    @Test func leavesOtherKeysBehind() {
        withDomains { old, new in
            old.set(false, forKey: "livePreview")
            old.set(true, forKey: "NSStatusItem Visible Item-0")
            SettingsMigration.run(from: old, to: new)
            #expect(new.object(forKey: "livePreview") as? Bool == false)
            #expect(new.object(forKey: "NSStatusItem Visible Item-0") == nil)
        }
    }
}
