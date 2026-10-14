import Testing

@testable import FlickCore

@MainActor
@Suite struct InputRouterTests {
    let window = WindowHandle("finder-1")
    let press = GlobalPoint(x: 400, y: 210)
    let pointer = GlobalPoint(x: 450, y: 260)
    let windows = FakeWindows()

    var dragContext: GestureContext {
        GestureContext(
            window: window, pointer: pointer,
            drag: DragContext(frameAtPress: GlobalRect(x: 300, y: 200, width: 640, height: 480), pressPoint: press))
    }
    var swipeContext: GestureContext { GestureContext(window: window, pointer: pointer) }

    /// Both buttons on, so either scroll recognizer claims.
    static let both: FlickSettings = {
        var settings = FlickSettings()
        settings.scrollButton = .both
        return settings
    }()

    func makeRouter(onUpdate: @escaping (GestureUpdate) -> Void) -> InputRouter {
        windows.frames[window] = GlobalRect(x: 350, y: 250, width: 640, height: 480)
        let probe = FakeProbe(window: window)
        return InputRouter(
            gestures: GestureRecognizer(probe: probe, onUpdate: onUpdate),
            dragScroll: DragScrollRecognizer(
                probe: probe, windows: windows, settings: { Self.both }, onUpdate: onUpdate),
            holdScroll: HoldScrollRecognizer(probe: probe, settings: { Self.both }, onUpdate: onUpdate))
    }

    var holdContext: GestureContext { GestureContext(window: window, pointer: press) }

    func held(_ lines: Double) -> InputEvent {
        .holdScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: press)
    }

    func wheel(_ lines: Double) -> InputEvent {
        .dragScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: pointer)
    }

    func swipe(_ phase: GesturePhase, _ dx: Double = 0) -> InputEvent {
        .scroll(phase: phase, deltaX: dx, deltaY: 0, invertedFromDevice: true, location: pointer)
    }

    @Test func mouseEventsAndDragScrollsGoToTheDragRecognizer() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)]
        #expect(events.map { router.handle($0) } == [.passThrough, .swallow, .passThrough])
        #expect(updates == [.preview(dragContext, .slot(.fill)), .commit(dragContext, .slot(.fill))])
    }

    @Test func trackpadSwipesGoToTheGestureRecognizer() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        #expect([swipe(.began, -60), swipe(.ended)].map { router.handle($0) } == [.swallow, .swallow])
        #expect(updates == [.preview(swipeContext, .slot(.leftHalf)), .commit(swipeContext, .slot(.leftHalf))])
    }

    @Test func aTrackpadScrollDuringATrackedDragCancelsTheDrag() {
        // A trackpad scroll arrives without the button held: the release was lost.
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), swipe(.began, -60)]
        _ = events.map { router.handle($0) }
        #expect(updates == [.preview(dragContext, .slot(.fill)), .cancel, .preview(swipeContext, .slot(.leftHalf))])
    }

    @Test func aTrackpadScrollInFlightAtReleaseLeavesTheDragToCommit() {
        // The button went up before this scroll was translated, so it arrives as a plain scroll
        // just ahead of the mouse-up.
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [
            .mouseDown(location: press), wheel(1), swipe(.changed, -5), .mouseUp(location: pointer),
        ]
        _ = events.map { router.handle($0) }
        #expect(updates == [.preview(dragContext, .slot(.fill)), .commit(dragContext, .slot(.fill))])
    }

    @Test func resetCancelsATrackedDrag() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1)]
        _ = events.map { router.handle($0) }
        router.reset()
        #expect(updates == [.preview(dragContext, .slot(.fill)), .cancel])
    }

    @Test func resetCancelsASwipe() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        _ = router.handle(swipe(.began, -60))
        router.reset()
        #expect(updates == [.preview(swipeContext, .slot(.leftHalf)), .cancel])
    }

    @Test func pausingPausesAllThree() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        router.isPaused = true
        let events: [InputEvent] = [
            .mouseDown(location: press), wheel(1), .mouseUp(location: pointer), swipe(.began, -60), swipe(.ended),
            .rightMouseDown(location: press), held(1), .rightMouseUp(location: press),
        ]
        #expect(events.map { router.handle($0) } == Array(repeating: .passThrough, count: 8))
        #expect(updates.isEmpty)
    }

    @Test func rightButtonEventsAndHoldScrollsGoToTheHoldRecognizer() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.rightMouseDown(location: press), held(1), .rightMouseUp(location: press)]
        #expect(events.map { router.handle($0) } == [.swallow, .swallow, .swallow])
        #expect(updates == [.preview(holdContext, .slot(.fill)), .commit(holdContext, .slot(.fill))])
    }

    @Test func aTrackpadScrollThatBeginsCancelsATrackedHold() {
        // A trackpad scroll arrives without the button held: the release was lost.
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.rightMouseDown(location: press), held(1), swipe(.began, -60)]
        _ = events.map { router.handle($0) }
        #expect(updates == [.preview(holdContext, .slot(.fill)), .cancel, .preview(swipeContext, .slot(.leftHalf))])
    }

    @Test func resetCancelsATrackedHold() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.rightMouseDown(location: press), held(1)]
        _ = events.map { router.handle($0) }
        router.reset()
        #expect(updates == [.preview(holdContext, .slot(.fill)), .cancel])
    }
}
