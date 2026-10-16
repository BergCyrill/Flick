import Testing

@testable import FlickCore

@Suite struct ScrollLadderTests {
    /// Classic mouse wheel: rolling it away from you gives positive deltas.
    func wheel(_ notches: [Double]) -> ScrollLadder {
        var ladder = ScrollLadder()
        for lines in notches {
            ladder.scroll(deltaY: lines, precise: false, invertedFromDevice: false)
        }
        return ladder
    }

    /// Natural scrolling trackpad: fingers moving away give negative deltas.
    func fingers(_ points: [Double]) -> ScrollLadder {
        var ladder = ScrollLadder()
        for away in points {
            ladder.scroll(deltaY: -away, precise: true, invertedFromDevice: true)
        }
        return ladder
    }

    @Test func startsWithoutATarget() {
        #expect(ScrollLadder().target == nil)
    }

    @Test func oneNotchAwayFillsAndOneTowardsRestores() {
        #expect(wheel([1]).target == .slot(.fill))
        #expect(wheel([-1]).target == .restore)
    }

    @Test func naturalScrollingGivesTheSameDirection() {
        var ladder = ScrollLadder()
        ladder.scroll(deltaY: -1, precise: false, invertedFromDevice: true)
        #expect(ladder.target == .slot(.fill))
    }

    @Test func eachNotchAwayStepsToTheNextSlot() {
        let expected: [Slot] = [
            .fill, .leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .topHalf, .bottomHalf,
        ]
        for (index, slot) in expected.enumerated() {
            #expect(wheel(Array(repeating: 1, count: index + 1)).target == .slot(slot))
        }
    }

    @Test func aFastSpinStillMovesOneSlotPerNotch() {
        #expect(wheel([6]).target == .slot(.fill))
        #expect(wheel([6, 4]).target == .slot(.leftHalf))
    }

    @Test func scrollingBackStepsBackAndCancelsAtTheStart() {
        #expect(wheel([1, 1, 1, -1]).target == .slot(.leftHalf))
        #expect(wheel([1, -1]).target == nil)
    }

    @Test func stopsAtBothEndsSoTheWayBackIsImmediate() {
        #expect(wheel(Array(repeating: 1, count: 15) + [-1]).target == .slot(.topHalf))
        #expect(wheel([-1, -1, -1, 1]).target == nil)
    }

    @Test func aTrackpadFillsAfterTwentyPointsThenStepsEveryForty() {
        #expect(fingers([19]).target == nil)
        #expect(fingers([15, 5]).target == .slot(.fill))
        #expect(fingers([59]).target == .slot(.fill))
        #expect(fingers([60]).target == .slot(.leftHalf))
        #expect(fingers([100]).target == .slot(.rightHalf))
        #expect(fingers([-20]).target == .restore)
    }

    @Test func withoutCyclingItStopsAtFillAsBefore() {
        var ladder = ScrollLadder(cycles: false)
        for _ in 0..<5 {
            ladder.scroll(deltaY: 1, precise: false, invertedFromDevice: false)
        }
        #expect(ladder.target == .slot(.fill))
        ladder.scroll(deltaY: -1, precise: false, invertedFromDevice: false)
        #expect(ladder.target == nil)
        ladder.scroll(deltaY: -1, precise: false, invertedFromDevice: false)
        #expect(ladder.target == .restore)
    }

    @Test func withoutCyclingATrackpadAlsoStopsAtFill() {
        var ladder = ScrollLadder(cycles: false)
        ladder.scroll(deltaY: -500, precise: true, invertedFromDevice: true)
        #expect(ladder.target == .slot(.fill))
        ladder.scroll(deltaY: 1, precise: true, invertedFromDevice: true)
        #expect(ladder.target == nil)
    }

    @Test func aTrackpadAlsoStopsAtTheEnds() {
        #expect(fingers([2000]).target == .slot(.bottomHalf))
        #expect(fingers([2000, -40]).target == .slot(.topHalf))
        #expect(fingers([-500, 20]).target == nil)
    }
}
