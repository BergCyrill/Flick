import Testing

@testable import FlickCore

@Suite struct DragRestoreTests {
    let visible = GlobalRect(x: 0, y: 25, width: 1440, height: 875)
    /// The restore frame; only its 640×480 size matters.
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    /// A left-half window grabbed in the middle of its titlebar, 12 pt below its top edge.
    let drag = DragContext(
        frameAtPress: GlobalRect(x: 8, y: 33, width: 708, height: 859), pressPoint: GlobalPoint(x: 362, y: 45))

    func restored(at pointer: GlobalPoint) -> GlobalRect {
        DragRestore.frame(restoring: original, drag: drag, pointer: pointer, visible: visible)
    }

    @Test func keepsTheGrabbedSpotUnderThePointer() {
        #expect(restored(at: GlobalPoint(x: 700, y: 300)) == GlobalRect(x: 380, y: 288, width: 640, height: 480))
    }

    @Test func keepsTheRelativeHorizontalGrabPosition() {
        // Grabbed a quarter of the way along the titlebar.
        let quarter = DragContext(frameAtPress: drag.frameAtPress, pressPoint: GlobalPoint(x: 185, y: 45))
        let frame = DragRestore.frame(
            restoring: original, drag: quarter, pointer: GlobalPoint(x: 700, y: 300), visible: visible)
        #expect(frame == GlobalRect(x: 540, y: 288, width: 640, height: 480))
    }

    @Test func staysInsideTheRightEdge() {
        #expect(restored(at: GlobalPoint(x: 1400, y: 300)) == GlobalRect(x: 800, y: 288, width: 640, height: 480))
    }

    @Test func staysInsideTheLeftEdge() {
        #expect(restored(at: GlobalPoint(x: 100, y: 300)) == GlobalRect(x: 0, y: 288, width: 640, height: 480))
    }

    @Test func staysBelowTheMenuBar() {
        #expect(restored(at: GlobalPoint(x: 700, y: 20)) == GlobalRect(x: 380, y: 25, width: 640, height: 480))
    }

    @Test func staysAboveTheBottomEdge() {
        #expect(restored(at: GlobalPoint(x: 700, y: 880)) == GlobalRect(x: 380, y: 420, width: 640, height: 480))
    }

    @Test func topOffsetIsCappedToTheRestoredHeight() {
        // Grabbed 500 pt below the top of a filled window; the restored window is only 480 tall.
        let deep = DragContext(
            frameAtPress: GlobalRect(x: 0, y: 25, width: 1440, height: 875), pressPoint: GlobalPoint(x: 720, y: 525))
        let frame = DragRestore.frame(
            restoring: original, drag: deep, pointer: GlobalPoint(x: 720, y: 700), visible: visible)
        #expect(frame == GlobalRect(x: 400, y: 220, width: 640, height: 480))
    }

    @Test func aWindowLargerThanTheScreenAlignsTopLeft() {
        let huge = GlobalRect(x: 0, y: 0, width: 2000, height: 1000)
        let frame = DragRestore.frame(
            restoring: huge, drag: drag, pointer: GlobalPoint(x: 700, y: 300), visible: visible)
        #expect(frame == GlobalRect(x: 0, y: 25, width: 2000, height: 1000))
    }

    @Test func worksOnASecondaryDisplayWithNegativeOrigin() {
        let left = GlobalRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = DragRestore.frame(
            restoring: original, drag: drag, pointer: GlobalPoint(x: -960, y: 400), visible: left)
        #expect(frame == GlobalRect(x: -1280, y: 388, width: 640, height: 480))
    }

    @Test func roundsToWholePoints() {
        // Grabbed a third of the way along: 100 × 1/3 is not a whole number.
        let third = DragContext(
            frameAtPress: GlobalRect(x: 0, y: 25, width: 300, height: 400), pressPoint: GlobalPoint(x: 100, y: 35))
        let small = GlobalRect(x: 0, y: 0, width: 100, height: 100)
        let frame = DragRestore.frame(
            restoring: small, drag: third, pointer: GlobalPoint(x: 500, y: 300), visible: visible)
        #expect(frame == GlobalRect(x: 467, y: 290, width: 100, height: 100))
    }
}

@MainActor
@Suite struct DragEventsInTheTrackpadRecognizerTests {
    @Test func mouseAndDragScrollEventsPassThroughTheTrackpadRecognizer() {
        let point = GlobalPoint(x: 400, y: 210)
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: FakeProbe(window: WindowHandle("w"))) { updates.append($0) }
        let events: [InputEvent] = [
            .mouseDown(location: point), .mouseDragged(location: point),
            .dragScroll(deltaY: 1, precise: false, invertedFromDevice: false, location: point),
            .mouseUp(location: point),
        ]
        #expect(events.map { recognizer.handle($0) } == Array(repeating: .passThrough, count: 4))
        #expect(updates.isEmpty)
    }
}
