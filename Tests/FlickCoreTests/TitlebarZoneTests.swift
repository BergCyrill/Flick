import Testing

@testable import FlickCore

@Suite struct TitlebarZoneTests {
    let window = GlobalRect(x: 100, y: 50, width: 800, height: 600)

    @Test func topFortyPointsCount() {
        #expect(TitlebarZone.contains(GlobalPoint(x: 400, y: 50), windowFrame: window, isFullScreen: false))
        #expect(TitlebarZone.contains(GlobalPoint(x: 400, y: 89.9), windowFrame: window, isFullScreen: false))
    }

    @Test func windowBodyAndOutsideDoNotCount() {
        #expect(!TitlebarZone.contains(GlobalPoint(x: 400, y: 90), windowFrame: window, isFullScreen: false))
        #expect(!TitlebarZone.contains(GlobalPoint(x: 99, y: 60), windowFrame: window, isFullScreen: false))
    }

    @Test func fullScreenWindowsHaveNoTitlebarZone() {
        #expect(!TitlebarZone.contains(GlobalPoint(x: 400, y: 60), windowFrame: window, isFullScreen: true))
    }

    @Test func zoneNeverExtendsBelowAShortWindow() {
        let short = GlobalRect(x: 0, y: 0, width: 300, height: 30)
        #expect(TitlebarZone.contains(GlobalPoint(x: 10, y: 29), windowFrame: short, isFullScreen: false))
        #expect(!TitlebarZone.contains(GlobalPoint(x: 10, y: 35), windowFrame: short, isFullScreen: false))
    }
}
