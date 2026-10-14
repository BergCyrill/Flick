import Testing

@testable import FlickCore

@Suite struct ScrollTargetTests {
    @Test func aWheelRolledAwayFromYouCountsPositive() {
        #expect(ScrollTarget.step(deltaY: 1, invertedFromDevice: false) == 1)
        #expect(ScrollTarget.step(deltaY: -1, invertedFromDevice: false) == -1)
    }

    @Test func naturalScrollingFlipsTheSign() {
        #expect(ScrollTarget.step(deltaY: -1, invertedFromDevice: true) == 1)
    }

    @Test func oneWheelLineFillsOrRestores() {
        #expect(ScrollTarget.target(amount: 1, precise: false) == .slot(.fill))
        #expect(ScrollTarget.target(amount: -1, precise: false) == .restore)
        #expect(ScrollTarget.target(amount: 0.5, precise: false) == nil)
    }

    @Test func aTrackpadNeedsTwentyPoints() {
        #expect(ScrollTarget.target(amount: 19, precise: true) == nil)
        #expect(ScrollTarget.target(amount: 20, precise: true) == .slot(.fill))
        #expect(ScrollTarget.target(amount: -20, precise: true) == .restore)
    }
}
