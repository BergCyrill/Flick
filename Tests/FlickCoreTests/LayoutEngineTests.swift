import Testing

@testable import FlickCore

@Suite struct LayoutEngineTests {
    // 1440×900 display with a 25 pt menu bar and no Dock, in top-left coordinates.
    let visible = GlobalRect(x: 0, y: 25, width: 1440, height: 875)

    @Test(arguments: [
        (Slot.leftHalf, GlobalRect(x: 8, y: 33, width: 708, height: 859)),
        (.rightHalf, GlobalRect(x: 724, y: 33, width: 708, height: 859)),
        (.topHalf, GlobalRect(x: 8, y: 33, width: 1424, height: 425)),
        (.bottomHalf, GlobalRect(x: 8, y: 467, width: 1424, height: 425)),
        (.topLeft, GlobalRect(x: 8, y: 33, width: 708, height: 425)),
        (.topRight, GlobalRect(x: 724, y: 33, width: 708, height: 425)),
        (.bottomLeft, GlobalRect(x: 8, y: 467, width: 708, height: 425)),
        (.bottomRight, GlobalRect(x: 724, y: 467, width: 708, height: 425)),
        (.fill, GlobalRect(x: 8, y: 33, width: 1424, height: 859)),
    ])
    func slotFrames(slot: Slot, expected: GlobalRect) {
        #expect(LayoutEngine.frame(for: slot, in: visible) == expected)
    }

    @Test(arguments: Slot.allCases)
    func everySlotKeepsTheOuterGap(slot: Slot) {
        let frame = LayoutEngine.frame(for: slot, in: visible)
        #expect(frame.minX >= visible.minX + 8)
        #expect(frame.minY >= visible.minY + 8)
        #expect(frame.maxX <= visible.maxX - 8)
        #expect(frame.maxY <= visible.maxY - 8)
    }

    @Test func neighboursAreSeparatedByAtLeastTheGap() {
        let left = LayoutEngine.frame(for: .topLeft, in: visible)
        let right = LayoutEngine.frame(for: .topRight, in: visible)
        let below = LayoutEngine.frame(for: .bottomLeft, in: visible)
        #expect(right.minX - left.maxX >= 8)
        #expect(right.minX - left.maxX <= 9)
        #expect(below.minY - left.maxY >= 8)
        #expect(below.minY - left.maxY <= 9)
    }

    @Test func worksOnASecondaryDisplayWithNegativeOrigin() {
        let secondary = GlobalRect(x: 1440, y: -1055, width: 1920, height: 1055)
        #expect(
            LayoutEngine.frame(for: .leftHalf, in: secondary)
                == GlobalRect(x: 1448, y: -1047, width: 948, height: 1039))
        #expect(
            LayoutEngine.frame(for: .bottomRight, in: secondary)
                == GlobalRect(x: 2404, y: -523, width: 948, height: 515))
    }

    @Test func roundsFractionalVisibleFramesToWholePoints() {
        let fractional = GlobalRect(x: 0.5, y: 24.5, width: 1511, height: 957.5)
        for slot in Slot.allCases {
            let frame = LayoutEngine.frame(for: slot, in: fractional)
            #expect(frame.x == frame.x.rounded())
            #expect(frame.y == frame.y.rounded())
            #expect(frame.width == frame.width.rounded())
            #expect(frame.height == frame.height.rounded())
        }
    }
}
