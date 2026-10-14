import Foundation
import Testing

@testable import FlickCore

@Suite struct FlickSettingsTests {
    /// Runs `body` with a private defaults domain and removes the domain afterwards.
    func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "local.personal.flick.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func gesturesAreOnByDefaultWithTheLeftButton() {
        let settings = FlickSettings()
        #expect(settings.swipeToSnap)
        #expect(settings.pinchToFillRestore)
        #expect(settings.scrollButton == .left)
        #expect(settings.livePreview)
    }

    @Test func keysThatWereNeverWrittenKeepTheirDefaults() {
        withDefaults { defaults in
            #expect(FlickSettings(defaults: defaults) == FlickSettings())
        }
    }

    @Test func savedSettingsReadBack() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.pinchToFillRestore = false
            settings.scrollButton = .both
            settings.livePreview = false
            settings.save(to: defaults)
            #expect(FlickSettings(defaults: defaults) == settings)
        }
    }

    @Test func eachSwitchIsStoredUnderItsOwnKey() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.livePreview = false
            settings.save(to: defaults)
            #expect(defaults.object(forKey: "livePreview") as? Bool == false)
            #expect(defaults.object(forKey: "swipeToSnap") as? Bool == true)
        }
    }

    @Test func theScrollButtonIsStoredByName() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.scrollButton = .right
            settings.save(to: defaults)
            #expect(defaults.string(forKey: "scrollButton") == "right")
        }
    }

    @Test func theOldSwitchOnBecomesTheLeftButton() {
        withDefaults { defaults in
            defaults.set(true, forKey: "scrollWhileDragging")
            #expect(FlickSettings(defaults: defaults).scrollButton == .left)
        }
    }

    @Test func theOldSwitchOffBecomesOff() {
        withDefaults { defaults in
            defaults.set(false, forKey: "scrollWhileDragging")
            #expect(FlickSettings(defaults: defaults).scrollButton == .off)
        }
    }

    @Test func theScrollButtonWinsOverTheOldSwitch() {
        withDefaults { defaults in
            defaults.set(false, forKey: "scrollWhileDragging")
            defaults.set("right", forKey: "scrollButton")
            #expect(FlickSettings(defaults: defaults).scrollButton == .right)
        }
    }

    @Test func anUnknownScrollButtonKeepsTheDefault() {
        withDefaults { defaults in
            defaults.set("middle", forKey: "scrollButton")
            #expect(FlickSettings(defaults: defaults).scrollButton == .left)
        }
    }

    @Test func eachChoiceIncludesItsButtons() {
        #expect(ScrollButton.allCases.map(\.includesLeft) == [false, true, false, true])
        #expect(ScrollButton.allCases.map(\.includesRight) == [false, false, true, true])
    }
}
