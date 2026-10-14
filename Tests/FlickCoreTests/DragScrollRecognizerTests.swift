import Testing

@testable import FlickCore

@MainActor
@Suite struct DragScrollRecognizerTests {
    let window = WindowHandle("finder-1")
    /// The window when the button went down; its titlebar zone is y 200..<240.
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    let press = GlobalPoint(x: 400, y: 210)
    /// 50 pt right and down from the press.
    let pointer = GlobalPoint(x: 450, y: 260)
    /// The window has moved along with the pointer.
    static let dragged = GlobalRect(x: 350, y: 250, width: 640, height: 480)
    let windows = FakeWindows()

    var context: GestureContext {
        GestureContext(window: window, pointer: pointer, drag: DragContext(frameAtPress: original, pressPoint: press))
    }

    /// Classic scrolling mouse wheel: rolling it away from you gives positive deltas.
    func wheel(_ lines: Double) -> InputEvent {
        .dragScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: pointer)
    }

    func run(
        _ events: [InputEvent], probe: FakeProbe? = nil, windowFrame: GlobalRect? = DragScrollRecognizerTests.dragged,
        settings: FlickSettings = FlickSettings()
    ) -> (decisions: [EventDecision], updates: [GestureUpdate]) {
        windows.frames[window] = windowFrame
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(
            probe: probe ?? FakeProbe(window: window), windows: windows, settings: { settings },
            onUpdate: { updates.append($0) })
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    @Test func scrollingAwayWhileDraggingPreviewsFillAndReleaseCommitsIt() {
        let result = run([
            .mouseDown(location: press), .mouseDragged(location: pointer), wheel(1), .mouseUp(location: pointer),
        ])
        #expect(result.decisions == [.passThrough, .passThrough, .swallow, .passThrough])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func scrollingTowardsYouTargetsRestore() {
        let result = run([.mouseDown(location: press), wheel(-1), .mouseUp(location: pointer)])
        #expect(result.updates == [.preview(context, .restore), .commit(context, .restore)])
    }

    @Test func naturalScrollingGivesTheSameDirection() {
        // Natural scrolling flips the deltas and says so.
        let away = InputEvent.dragScroll(deltaY: -1, precise: false, invertedFromDevice: true, location: pointer)
        let result = run([.mouseDown(location: press), away])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func aTrackpadNeedsTwentyPoints() {
        // Natural scrolling trackpad: fingers moving away give negative deltas.
        func fingers(_ points: Double) -> InputEvent {
            .dragScroll(deltaY: -points, precise: true, invertedFromDevice: true, location: pointer)
        }
        let result = run([.mouseDown(location: press), fingers(15), fingers(5)])
        #expect(result.decisions == [.passThrough, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func scrollingBackToNeutralCancels() {
        let result = run([.mouseDown(location: press), wheel(1), wheel(-1), .mouseUp(location: pointer)])
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(context, nil), .cancel])
    }

    @Test func pointerOffEveryTitlebarIsNotClaimedAndNotRetried() {
        let probe = FakeProbe(window: nil)
        windows.frames[window] = Self.dragged
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(probe: probe, windows: windows) { updates.append($0) }
        _ = recognizer.handle(.mouseDown(location: press))
        let first = recognizer.handle(wheel(1))
        probe.window = window
        let second = recognizer.handle(wheel(1))
        #expect([first, second] == [.passThrough, .passThrough])
        #expect(probe.probedPoints.count == 1)
        #expect(updates.isEmpty)
    }

    @Test func aFrameReadFailureIsNotClaimed() {
        let result = run([.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], windowFrame: nil)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
    }

    @Test func scrollWithoutAPressPassesThrough() {
        let probe = FakeProbe(window: window)
        let result = run([wheel(1)], probe: probe)
        #expect(result.decisions == [.passThrough])
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func theNextPressCancelsADragWhoseReleaseWasLost() {
        let result = run([.mouseDown(location: press), wheel(1), .mouseDown(location: press)])
        #expect(result.updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func resetCancelsAClaimedDrag() {
        windows.frames[window] = Self.dragged
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(probe: FakeProbe(window: window), windows: windows) {
            updates.append($0)
        }
        _ = recognizer.handle(.mouseDown(location: press))
        _ = recognizer.handle(wheel(1))
        recognizer.reset()
        _ = recognizer.handle(.mouseUp(location: pointer))
        #expect(updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func releaseWithoutScrollingDoesNothing() {
        let probe = FakeProbe(window: window)
        let result = run(
            [.mouseDown(location: press), .mouseDragged(location: pointer), .mouseUp(location: pointer)], probe: probe)
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func offInSettingsClaimsNothing() {
        var settings = FlickSettings()
        settings.scrollWhileDragging = false
        let probe = FakeProbe(window: window)
        let result = run(
            [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func pausedClaimsNothing() {
        windows.frames[window] = Self.dragged
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(probe: FakeProbe(window: window), windows: windows) {
            updates.append($0)
        }
        recognizer.isPaused = true
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)]
        #expect(events.map { recognizer.handle($0) } == [.passThrough, .passThrough, .passThrough])
        #expect(updates.isEmpty)
    }

    @Test func settingsAreReadOncePerDrag() {
        windows.frames[window] = Self.dragged
        let box = SettingsBox()
        let recognizer = DragScrollRecognizer(
            probe: FakeProbe(window: window), windows: windows, settings: { box.read() }, onUpdate: { _ in })
        let events: [InputEvent] = [
            .mouseDown(location: press), wheel(1), wheel(1), wheel(-1), .mouseUp(location: pointer),
        ]
        _ = events.map { recognizer.handle($0) }
        #expect(box.reads == 1)
    }

    @Test func thePreviewFollowsThePointer() {
        let later = GlobalPoint(x: 600, y: 400)
        let result = run([.mouseDown(location: press), wheel(1), .mouseDragged(location: later)])
        let moved = GestureContext(window: window, pointer: later, drag: context.drag)
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(moved, .slot(.fill))])
    }

    @Test func trackpadGesturesAndPinchesPassThrough() {
        let result = run([
            .mouseDown(location: press),
            .scroll(phase: .began, deltaX: 0, deltaY: -30, invertedFromDevice: true, location: pointer),
            .momentum(phase: .changed),
            .magnify(phase: .began, magnification: 0.3, location: pointer),
        ])
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
    }

    @Test func tracksFromPressToRelease() {
        let recognizer = DragScrollRecognizer(probe: FakeProbe(window: window), windows: windows) { _ in }
        #expect(!recognizer.isTracking)
        _ = recognizer.handle(.mouseDown(location: press))
        #expect(recognizer.isTracking)
        _ = recognizer.handle(.mouseUp(location: pointer))
        #expect(!recognizer.isTracking)
    }
}
