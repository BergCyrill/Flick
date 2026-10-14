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

    @Test func everythingIsOnByDefault() {
        let settings = FlickSettings()
        #expect(settings.swipeToSnap)
        #expect(settings.pinchToFillRestore)
        #expect(settings.scrollWhileDragging)
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
            settings.livePreview = false
            settings.save(to: defaults)
            #expect(FlickSettings(defaults: defaults) == settings)
        }
    }

    @Test func eachSwitchIsStoredUnderItsOwnKey() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.scrollWhileDragging = false
            settings.save(to: defaults)
            #expect(defaults.object(forKey: "scrollWhileDragging") as? Bool == false)
            #expect(defaults.object(forKey: "swipeToSnap") as? Bool == true)
        }
    }
}
