import Testing

@testable import FlickCore

@MainActor
final class FakeWindows: WindowAccess {
    var frames: [WindowHandle: GlobalRect] = [:]
    var refuseMoves = false
    private(set) var setCalls: [GlobalRect] = []

    func frame(of window: WindowHandle) -> GlobalRect? {
        frames[window]
    }

    func setFrame(_ frame: GlobalRect, of window: WindowHandle) -> Bool {
        setCalls.append(frame)
        guard !refuseMoves, frames[window] != nil else { return false }
        frames[window] = frame
        return true
    }
}

@MainActor
final class FakeScreens: ScreenProvider {
    var visible: GlobalRect? = GlobalRect(x: 0, y: 25, width: 1440, height: 875)

    func visibleFrame(containing point: GlobalPoint) -> GlobalRect? {
        visible
    }
}

@MainActor
final class FakePreview: PreviewPresenter {
    private(set) var shown: GlobalRect?
    private(set) var hideCount = 0

    func show(_ frame: GlobalRect) {
        shown = frame
    }

    func hide() {
        shown = nil
        hideCount += 1
    }
}

@Suite struct FrameHistoryTests {
    @Test func takeReturnsTheRecordedFrameOnce() {
        var history = FrameHistory()
        let window = WindowHandle(1)
        history.record(GlobalRect(x: 1, y: 2, width: 3, height: 4), for: window)
        #expect(history.peek(for: window) == GlobalRect(x: 1, y: 2, width: 3, height: 4))
        #expect(history.take(for: window) == GlobalRect(x: 1, y: 2, width: 3, height: 4))
        #expect(history.take(for: window) == nil)
    }

    @Test func windowsAreTrackedSeparately() {
        var history = FrameHistory()
        history.record(GlobalRect(x: 1, y: 1, width: 1, height: 1), for: WindowHandle(1))
        #expect(history.peek(for: WindowHandle(2)) == nil)
    }
}

@MainActor
@Suite struct FlickControllerTests {
    let window = WindowHandle("w")
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    let windows = FakeWindows()
    let screens = FakeScreens()
    let preview = FakePreview()
    var context: GestureContext { GestureContext(window: window, pointer: GlobalPoint(x: 400, y: 210)) }

    func makeController() -> FlickController {
        windows.frames[window] = original
        return FlickController(windows: windows, screens: screens, preview: preview)
    }

    @Test func previewShowsTheSlotFrame() {
        let controller = makeController()
        controller.handle(.preview(context, .slot(.topLeft)))
        #expect(preview.shown == GlobalRect(x: 8, y: 33, width: 708, height: 425))
    }

    @Test func previewWithoutTargetHides() {
        let controller = makeController()
        controller.handle(.preview(context, .slot(.topLeft)))
        controller.handle(.preview(context, nil))
        #expect(preview.shown == nil)
    }

    @Test func commitMovesTheWindowAndHidesThePreview() {
        let controller = makeController()
        controller.handle(.preview(context, .slot(.rightHalf)))
        controller.handle(.commit(context, .slot(.rightHalf)))
        #expect(windows.frames[window] == GlobalRect(x: 724, y: 33, width: 708, height: 859))
        #expect(preview.shown == nil)
    }

    @Test func restoreReturnsToTheFrameBeforeTheLastSnap() {
        let controller = makeController()
        controller.handle(.commit(context, .slot(.fill)))
        controller.handle(.preview(context, .restore))
        #expect(preview.shown == original)
        controller.handle(.commit(context, .restore))
        #expect(windows.frames[window] == original)
    }

    @Test func restoreWithoutHistoryDoesNothing() {
        let controller = makeController()
        controller.handle(.preview(context, .restore))
        #expect(preview.shown == nil)
        controller.handle(.commit(context, .restore))
        #expect(windows.setCalls.isEmpty)
        #expect(windows.frames[window] == original)
    }

    @Test func secondRestoreDoesNothing() {
        let controller = makeController()
        controller.handle(.commit(context, .slot(.leftHalf)))
        controller.handle(.commit(context, .restore))
        controller.handle(.commit(context, .restore))
        #expect(windows.setCalls.count == 2)
    }

    @Test func failedMoveIsNotRecorded() {
        let controller = makeController()
        windows.refuseMoves = true
        controller.handle(.commit(context, .slot(.leftHalf)))
        windows.refuseMoves = false
        controller.handle(.commit(context, .restore))
        #expect(windows.setCalls.count == 1)
    }

    @Test func windowThatDisappearedIsIgnored() {
        let controller = makeController()
        windows.frames[window] = nil
        controller.handle(.commit(context, .slot(.leftHalf)))
        #expect(windows.setCalls.isEmpty)
        #expect(preview.hideCount == 1)
    }

    @Test func pointerOffEveryScreenShowsNothing() {
        let controller = makeController()
        screens.visible = nil
        controller.handle(.preview(context, .slot(.leftHalf)))
        controller.handle(.commit(context, .slot(.leftHalf)))
        #expect(preview.shown == nil)
        #expect(windows.setCalls.isEmpty)
    }

    @Test func cancelHidesThePreview() {
        let controller = makeController()
        controller.handle(.preview(context, .slot(.leftHalf)))
        controller.handle(.cancel)
        #expect(preview.shown == nil)
    }
}
