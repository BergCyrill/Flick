import Testing

@testable import FlickCore

@MainActor
@Suite struct FlickControllerDragTests {
    let window = WindowHandle("w")
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    let left = GlobalRect(x: 8, y: 33, width: 708, height: 859)
    let windows = FakeWindows()
    let preview = FakePreview()
    var plain: GestureContext { GestureContext(window: window, pointer: GlobalPoint(x: 400, y: 210)) }

    func makeController() -> FlickController {
        windows.frames[window] = original
        return FlickController(windows: windows, screens: FakeScreens(), preview: preview)
    }

    /// Dragging the left-half window, grabbed mid-titlebar, with the pointer now at `pointer`.
    func dragOutOfLeftHalf(pointer: GlobalPoint) -> GestureContext {
        GestureContext(
            window: window, pointer: pointer,
            drag: DragContext(frameAtPress: left, pressPoint: GlobalPoint(x: 362, y: 45)))
    }

    @Test func dragFillKeepsTheRestorePointFromBeforeTheFirstSnap() {
        let controller = makeController()
        controller.handle(.commit(plain, .slot(.leftHalf)))
        // The user drags the snapped window 100 pt right and 60 pt down, then scrolls away.
        windows.frames[window] = GlobalRect(x: 108, y: 93, width: 708, height: 859)
        controller.handle(.commit(dragOutOfLeftHalf(pointer: GlobalPoint(x: 462, y: 105)), .slot(.fill)))
        controller.handle(.commit(plain, .restore))
        #expect(windows.frames[window] == original)
    }

    @Test func dragFillOfAnUnsnappedWindowRestoresToItsFrameAtThePress() {
        let controller = makeController()
        windows.frames[window] = GlobalRect(x: 350, y: 250, width: 640, height: 480)
        let drag = GestureContext(
            window: window, pointer: GlobalPoint(x: 450, y: 260),
            drag: DragContext(frameAtPress: original, pressPoint: GlobalPoint(x: 400, y: 210)))
        controller.handle(.commit(drag, .slot(.fill)))
        controller.handle(.commit(plain, .restore))
        #expect(windows.frames[window] == original)
    }

    @Test func dragRestorePutsTheRestoreSizeUnderThePointer() {
        let controller = makeController()
        controller.handle(.commit(plain, .slot(.leftHalf)))
        let drag = dragOutOfLeftHalf(pointer: GlobalPoint(x: 700, y: 300))
        let expected = GlobalRect(x: 380, y: 288, width: 640, height: 480)
        controller.handle(.preview(drag, .restore))
        #expect(preview.shown == expected)
        controller.handle(.commit(drag, .restore))
        #expect(windows.frames[window] == expected)
        controller.handle(.preview(drag, .restore))
        #expect(preview.shown == nil)
    }

    @Test func dragRestoreWithoutHistoryShowsAndDoesNothing() {
        let controller = makeController()
        let drag = dragOutOfLeftHalf(pointer: GlobalPoint(x: 700, y: 300))
        controller.handle(.preview(drag, .restore))
        controller.handle(.commit(drag, .restore))
        #expect(preview.showCount == 0)
        #expect(windows.setCalls.isEmpty)
    }

    @Test func anUnchangedPreviewIsNotShownAgain() {
        let controller = makeController()
        controller.handle(.preview(plain, .slot(.fill)))
        controller.handle(.preview(plain, .slot(.fill)))
        #expect(preview.showCount == 1)
        controller.handle(.cancel)
        controller.handle(.preview(plain, .slot(.fill)))
        #expect(preview.showCount == 2)
    }

    @Test func aRestorePreviewFollowsThePointer() {
        let controller = makeController()
        controller.handle(.commit(plain, .slot(.leftHalf)))
        controller.handle(.preview(dragOutOfLeftHalf(pointer: GlobalPoint(x: 700, y: 300)), .restore))
        controller.handle(.preview(dragOutOfLeftHalf(pointer: GlobalPoint(x: 720, y: 300)), .restore))
        #expect(preview.showCount == 2)
        #expect(preview.shown == GlobalRect(x: 400, y: 288, width: 640, height: 480))
    }
}
