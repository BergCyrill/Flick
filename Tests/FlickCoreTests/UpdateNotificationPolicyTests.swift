import Foundation
import Testing

@testable import FlickCore

@Suite struct UpdateNotificationPolicyTests {
    /// Runs `body` with a private defaults domain and removes it afterwards.
    func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "io.github.bergcyrill.flick.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func notifiesAboutAVersionOnce() {
        withDefaults { defaults in
            let policy = UpdateNotificationPolicy(defaults: defaults)
            #expect(policy.shouldNotify(about: "70"))
            #expect(!policy.shouldNotify(about: "70"))
        }
    }

    @Test func remembersTheVersionAcrossLaunches() {
        withDefaults { defaults in
            _ = UpdateNotificationPolicy(defaults: defaults).shouldNotify(about: "70")
            #expect(!UpdateNotificationPolicy(defaults: defaults).shouldNotify(about: "70"))
        }
    }

    @Test func notifiesAgainAboutANewerVersion() {
        withDefaults { defaults in
            let policy = UpdateNotificationPolicy(defaults: defaults)
            _ = policy.shouldNotify(about: "70")
            #expect(policy.shouldNotify(about: "71"))
        }
    }
}
