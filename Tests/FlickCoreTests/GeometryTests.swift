import Testing

@testable import FlickCore

@Suite struct GeometryTests {
    @Test func containsIsHalfOpen() {
        let rect = GlobalRect(x: 10, y: 20, width: 100, height: 40)
        #expect(rect.contains(GlobalPoint(x: 10, y: 20)))
        #expect(rect.contains(GlobalPoint(x: 109.9, y: 59.9)))
        #expect(!rect.contains(GlobalPoint(x: 110, y: 30)))
        #expect(!rect.contains(GlobalPoint(x: 50, y: 60)))
        #expect(!rect.contains(GlobalPoint(x: 9.9, y: 30)))
    }

    @Test func flipsPrimaryVisibleFrameBelowMenuBar() {
        // 1440×900 primary display, Dock 70 pt high at the bottom, menu bar 25 pt.
        let appKitVisible = GlobalRect(x: 0, y: 70, width: 1440, height: 805)
        #expect(appKitVisible.flipped(primaryHeight: 900) == GlobalRect(x: 0, y: 25, width: 1440, height: 805))
    }

    @Test func flipsSecondaryDisplayAbovePrimaryToNegativeY() {
        let appKitFrame = GlobalRect(x: 0, y: 900, width: 1920, height: 1080)
        #expect(appKitFrame.flipped(primaryHeight: 900) == GlobalRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    @Test func flippingTwiceIsIdentity() {
        let rect = GlobalRect(x: -300, y: 42, width: 800, height: 600)
        #expect(rect.flipped(primaryHeight: 1117).flipped(primaryHeight: 1117) == rect)
    }
}
