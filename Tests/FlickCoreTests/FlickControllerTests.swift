import Testing

@testable import FlickCore

@MainActor
final class FakeWindows: WindowAccess {
    var frames: [WindowHandle: GlobalRect] = [:]
    var refuseMoves = false
    /// Imitates apps that adjust the requested frame, e.g. Terminal rounding to its character grid.
    var adjust: (GlobalRect) -> GlobalRect = { $0 }
    private(set) var setCalls: [GlobalRect] = []

    func frame(of window: WindowHandle) -> GlobalRect? {
        frames[window]
    }

    func setFrame(_ frame: GlobalRect, of window: WindowHandle) -> Bool {
        setCalls.append(frame)
        guard !refuseMoves, frames[window] != nil else { return false }
        frames[window] = adjust(frame)
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
    let window = WindowHandle(1)
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    let left = GlobalRect(x: 8, y: 33, width: 708, height: 859)
    let right = GlobalRect(x: 724, y: 33, width: 708, height: 859)

    @Test func takeReturnsTheOriginalFrameOnce() {
        var history = FrameHistory()
        history.recordMove(from: original, to: left, for: window)
        #expect(history.peek(for: window) == original)
        #expect(history.take(for: window) == original)
        #expect(history.take(for: window) == nil)
    }

    @Test func windowsAreTrackedSeparately() {
        var history = FrameHistory()
        history.recordMove(from: original, to: left, for: window)
        #expect(history.peek(for: WindowHandle(2)) == nil)
    }

    @Test func movingOnFromWhereFlickPlacedItKeepsTheOriginal() {
        var history = FrameHistory()
        history.recordMove(from: original, to: left, for: window)
        history.recordMove(from: left, to: right, for: window)
        #expect(history.peek(for: window) == original)
    }

    @Test func driftWithinTwoPointsStillCountsAsPlaced() {
        var history = FrameHistory()
        history.recordMove(from: original, to: left, for: window)
        let drifted = GlobalRect(x: left.x + 2, y: left.y - 1, width: left.width, height: left.height)
        history.recordMove(from: drifted, to: right, for: window)
        #expect(history.peek(for: window) == original)
    }

    @Test func largerDriftStartsANewRun() {
        var history = FrameHistory()
        history.recordMove(from: original, to: left, for: window)
        let moved = GlobalRect(x: left.x + 3, y: left.y, width: left.width, height: left.height)
        history.recordMove(from: moved, to: right, for: window)
        #expect(history.peek(for: window) == moved)
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

    @Test func repeatedSnapsRestoreToTheFrameBeforeTheFirstSnap() {
        let controller = makeController()
        controller.handle(.commit(context, .slot(.leftHalf)))
        controller.handle(.commit(context, .slot(.rightHalf)))
        controller.handle(.commit(context, .slot(.fill)))
        controller.handle(.commit(context, .restore))
        #expect(windows.frames[window] == original)
    }

    @Test func movingTheWindowByHandStartsANewRun() {
        let controller = makeController()
        let byHand = GlobalRect(x: 500, y: 300, width: 400, height: 300)
        controller.handle(.commit(context, .slot(.leftHalf)))
        windows.frames[window] = byHand
        controller.handle(.commit(context, .slot(.rightHalf)))
        controller.handle(.commit(context, .restore))
        #expect(windows.frames[window] == byHand)
    }

    @Test func appAdjustedFrameStillCountsAsUntouched() {
        let controller = makeController()
        // Like Terminal: widths snap down to a 7 pt character grid.
        windows.adjust = { GlobalRect(x: $0.x, y: $0.y, width: ($0.width / 7).rounded(.down) * 7, height: $0.height) }
        controller.handle(.commit(context, .slot(.leftHalf)))
        controller.handle(.commit(context, .slot(.rightHalf)))
        controller.handle(.commit(context, .restore))
        // The restore itself is snapped to the grid again, so check what Flick asked for.
        #expect(windows.setCalls.last == original)
    }

    @Test func snappingAfterARestoreRecordsAFreshOriginal() {
        let controller = makeController()
        let byHand = GlobalRect(x: 500, y: 300, width: 400, height: 300)
        controller.handle(.commit(context, .slot(.leftHalf)))
        controller.handle(.commit(context, .restore))
        windows.frames[window] = byHand
        controller.handle(.commit(context, .slot(.fill)))
        controller.handle(.commit(context, .restore))
        #expect(windows.frames[window] == byHand)
    }
}
