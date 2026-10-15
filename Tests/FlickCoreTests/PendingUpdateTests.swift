import Foundation
import Testing

@testable import FlickCore

@Suite struct PendingUpdateTests {
    /// Runs `body` with a private defaults domain and removes it afterwards.
    func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "io.github.bergcyrill.flick.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func showsAnUpdateAScheduledCheckFound() {
        withDefaults { defaults in
            var pending = PendingUpdate(defaults: defaults)
            pending.found("0.9.0")
            #expect(pending.version == "0.9.0")
        }
    }

    @Test func keepsAPostponedUpdate() {
        withDefaults { defaults in
            var pending = PendingUpdate(defaults: defaults)
            pending.found("0.9.0")
            pending.userChose(.later, version: "0.9.0")
            #expect(pending.version == "0.9.0")
        }
    }

    @Test func showsAnUpdatePostponedFromAManualCheck() {
        withDefaults { defaults in
            var pending = PendingUpdate(defaults: defaults)
            pending.userChose(.later, version: "0.9.0")
            #expect(pending.version == "0.9.0")
        }
    }

    @Test func forgetsAnInstalledOrSkippedUpdate() {
        withDefaults { defaults in
            for choice in [PendingUpdate.Choice.install, .skip] {
                var pending = PendingUpdate(defaults: defaults)
                pending.found("0.9.0")
                pending.userChose(choice, version: "0.9.0")
                #expect(pending.version == nil)
                #expect(!PendingUpdate(defaults: defaults).takeWaitingFromLastLaunch())
            }
        }
    }

    @Test func remembersAWaitingUpdateForTheNextLaunchOnce() {
        withDefaults { defaults in
            var pending = PendingUpdate(defaults: defaults)
            pending.found("0.9.0")
            let next = PendingUpdate(defaults: defaults)
            #expect(next.version == nil)
            #expect(next.takeWaitingFromLastLaunch())
            #expect(!next.takeWaitingFromLastLaunch())
        }
    }

    @Test func nothingWaitsOnAFirstLaunch() {
        withDefaults { defaults in
            #expect(!PendingUpdate(defaults: defaults).takeWaitingFromLastLaunch())
        }
    }
}
