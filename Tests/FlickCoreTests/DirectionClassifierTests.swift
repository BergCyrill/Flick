import Foundation
import Testing

@testable import FlickCore

@Suite struct DirectionClassifierTests {
    /// A finger movement of `length` points at `degrees` (0 = right, 90 = down).
    func move(_ degrees: Double, length: Double = 100) -> (dx: Double, dy: Double) {
        let radians = degrees * .pi / 180
        return (cos(radians) * length, sin(radians) * length)
    }

    @Test(arguments: [
        (0.0, Slot.rightHalf), (45, .bottomRight), (90, .bottomHalf), (135, .bottomLeft),
        (180, .leftHalf), (225, .topLeft), (270, .topHalf), (315, .topRight),
    ])
    func eightDirections(degrees: Double, expected: Slot) {
        let finger = move(degrees)
        #expect(DirectionClassifier.slot(dx: finger.dx, dy: finger.dy) == expected)
    }

    @Test(arguments: [
        (22.4, Slot.rightHalf), (22.6, .bottomRight),
        (337.6, .rightHalf), (337.4, .topRight),
        (202.4, .leftHalf), (202.6, .topLeft),
    ])
    func sectorBoundariesAt22point5Degrees(degrees: Double, expected: Slot) {
        let finger = move(degrees)
        #expect(DirectionClassifier.slot(dx: finger.dx, dy: finger.dy) == expected)
    }

    @Test func belowMinimumDistanceHasNoSlot() {
        #expect(DirectionClassifier.slot(dx: 0, dy: 0) == nil)
        #expect(DirectionClassifier.slot(dx: -27, dy: -28) == nil)  // ~38.9 pt
        #expect(DirectionClassifier.slot(dx: -29, dy: -29) == .topLeft)  // ~41 pt
    }

    @Test func naturalScrollingDeltasFollowTheFingers() {
        let finger = DirectionClassifier.fingerDelta(
            scrollingDeltaX: -5, scrollingDeltaY: -7, invertedFromDevice: true)
        #expect(finger.dx == -5)
        #expect(finger.dy == -7)
    }

    @Test func classicScrollingDeltasAreNegated() {
        let finger = DirectionClassifier.fingerDelta(
            scrollingDeltaX: -5, scrollingDeltaY: -7, invertedFromDevice: false)
        #expect(finger.dx == 5)
        #expect(finger.dy == 7)
    }
}
