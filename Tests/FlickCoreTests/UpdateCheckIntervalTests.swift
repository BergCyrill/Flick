import Foundation
import Testing

@testable import FlickCore

@Suite struct UpdateCheckIntervalTests {
    @Test func offersOneFourEightAndTwentyFourHours() {
        let hours: [TimeInterval] = [1, 4, 8, 24]
        #expect(UpdateCheckInterval.allCases.map(\.seconds) == hours.map { $0 * 3600 })
    }

    @Test func picksTheMatchingChoiceForAStoredInterval() {
        for choice in UpdateCheckInterval.allCases {
            #expect(UpdateCheckInterval(closestTo: choice.seconds) == choice)
        }
    }

    @Test func picksTheNearestChoiceForAnyOtherInterval() {
        #expect(UpdateCheckInterval(closestTo: 7200) == .hour)
        #expect(UpdateCheckInterval(closestTo: 6 * 3600) == .fourHours)
        #expect(UpdateCheckInterval(closestTo: 7 * 24 * 3600) == .day)
        #expect(UpdateCheckInterval(closestTo: 0) == .hour)
    }
}
