import Testing

@testable import FlickCore

@MainActor
final class FakeProbe: TitlebarProbe {
    var window: WindowHandle?
    private(set) var probedPoints: [GlobalPoint] = []

    init(window: WindowHandle?) {
        self.window = window
    }

    func window(atTitlebar point: GlobalPoint) -> WindowHandle? {
        probedPoints.append(point)
        return window
    }
}

@MainActor
@Suite struct GestureRecognizerTests {
    let window = WindowHandle("finder-1")
    let start = GlobalPoint(x: 600, y: 260)
    var context: GestureContext { GestureContext(window: window, pointer: start) }

    /// Natural scrolling: the deltas follow the fingers.
    func swipe(_ phase: GesturePhase, _ dx: Double = 0, _ dy: Double = 0) -> InputEvent {
        .scroll(phase: phase, deltaX: dx, deltaY: dy, invertedFromDevice: true, location: start)
    }

    func pinch(_ phase: GesturePhase, _ magnification: Double = 0) -> InputEvent {
        .magnify(phase: phase, magnification: magnification, location: start)
    }

    func run(_ events: [InputEvent], probe: FakeProbe, paused: Bool = false)
        -> (decisions: [EventDecision], updates: [GestureUpdate])
    {
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: probe) { updates.append($0) }
        recognizer.isPaused = paused
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    @Test func swipeUpLeftOnTitlebarSnapsTopLeftAndSwallowsEverything() {
        let result = run(
            [swipe(.mayBegin), swipe(.began, -10, -10), swipe(.changed, -30, -30), swipe(.ended)],
            probe: FakeProbe(window: window))
        #expect(result.decisions == [.passThrough, .swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.topLeft)), .commit(context, .slot(.topLeft))])
    }

    @Test func previewFollowsDirectionChangesAndOnlyFiresOnChange() {
        let result = run(
            [
                swipe(.began, -50, 0), swipe(.changed, -5, 0),  // left
                swipe(.changed, 0, -60),  // now up-left
                swipe(.ended),
            ],
            probe: FakeProbe(window: window))
        #expect(
            result.updates == [
                .preview(context, .slot(.leftHalf)),
                .preview(context, .slot(.topLeft)),
                .commit(context, .slot(.topLeft)),
            ])
    }

    @Test func swipingBackToTheStartCancels() {
        let result = run(
            [swipe(.began, 50, 0), swipe(.changed, -45, 0), swipe(.ended)],
            probe: FakeProbe(window: window))
        #expect(result.updates == [.preview(context, .slot(.rightHalf)), .preview(context, nil), .cancel])
    }

    @Test func classicScrollingIsNormalisedToFingerDirection() {
        // Classic scrolling: fingers moving right produce a negative deltaX.
        let event = InputEvent.scroll(
            phase: .began, deltaX: -60, deltaY: 0, invertedFromDevice: false, location: start)
        let result = run([event], probe: FakeProbe(window: window))
        #expect(result.updates == [.preview(context, .slot(.rightHalf))])
    }

    @Test func swipeOffTitlebarPassesThroughIncludingMomentum() {
        let probe = FakeProbe(window: nil)
        let result = run(
            [swipe(.began, -50, -50), swipe(.changed, -50, -50), swipe(.ended), .momentum(phase: .began)],
            probe: probe)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints == [start])
    }

    @Test func momentumAfterAClaimedSwipeIsSwallowedUntilItEnds() {
        let result = run(
            [
                swipe(.began, -60, 0), swipe(.ended),
                .momentum(phase: .began), .momentum(phase: .changed), .momentum(phase: .ended),
                .momentum(phase: .changed),  // stray event after the end
            ],
            probe: FakeProbe(window: window))
        #expect(result.decisions == [.swallow, .swallow, .swallow, .swallow, .swallow, .passThrough])
    }

    @Test func newSwipeDuringMomentumIsProbedAgain() {
        let probe = FakeProbe(window: window)
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: probe) { updates.append($0) }
        _ = recognizer.handle(swipe(.began, -60, 0))
        _ = recognizer.handle(swipe(.ended))
        _ = recognizer.handle(.momentum(phase: .began))
        probe.window = nil
        #expect(recognizer.handle(swipe(.began, 60, 0)) == .passThrough)
        #expect(recognizer.handle(.momentum(phase: .changed)) == .passThrough)
    }

    @Test func touchWithoutMovementIsIgnored() {
        let probe = FakeProbe(window: window)
        let result = run([swipe(.mayBegin), swipe(.cancelled)], probe: probe)
        #expect(result.decisions == [.passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func systemCancelledSwipeHidesPreview() {
        let result = run([swipe(.began, -60, 0), swipe(.cancelled)], probe: FakeProbe(window: window))
        #expect(result.decisions == [.swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.leftHalf)), .cancel])
    }

    @Test func pinchOutFillsPinchInRestores() {
        let out = run(
            [pinch(.began, 0.05), pinch(.changed, 0.08), pinch(.changed, 0.05), pinch(.ended)],
            probe: FakeProbe(window: window))
        #expect(out.decisions == [.swallow, .swallow, .swallow, .swallow])
        #expect(out.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])

        let inward = run([pinch(.began, -0.1), pinch(.changed, -0.1), pinch(.ended)], probe: FakeProbe(window: window))
        #expect(inward.updates == [.preview(context, .restore), .commit(context, .restore)])
    }

    @Test func smallPinchCancels() {
        let result = run([pinch(.began, 0.05), pinch(.changed, 0.05), pinch(.ended)], probe: FakeProbe(window: window))
        #expect(result.updates == [.cancel])
    }

    @Test func pinchOffTitlebarPassesThrough() {
        let result = run([pinch(.began, 0.3), pinch(.changed, 0.3), pinch(.ended)], probe: FakeProbe(window: nil))
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
    }

    @Test func pausedRecognizerClaimsNothing() {
        let probe = FakeProbe(window: window)
        let result = run(
            [swipe(.began, -60, 0), swipe(.ended), pinch(.began, 0.3), pinch(.ended)], probe: probe, paused: true)
        #expect(result.decisions.allSatisfy { $0 == .passThrough })
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func pausingMidGestureLetsTheGestureFinish() {
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: FakeProbe(window: window)) { updates.append($0) }
        _ = recognizer.handle(swipe(.began, -60, 0))
        recognizer.isPaused = true
        #expect(recognizer.handle(swipe(.ended)) == .swallow)
        #expect(updates.last == .commit(context, .slot(.leftHalf)))
    }

    @Test func scrollEventsDuringAPinchPassThroughAndDoNotDisturbIt() {
        let result = run(
            [pinch(.began, 0.2), swipe(.mayBegin), swipe(.began, 5, 5), swipe(.ended), pinch(.ended)],
            probe: FakeProbe(window: window))
        #expect(result.decisions == [.swallow, .passThrough, .passThrough, .passThrough, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func newSwipeAfterALostEndCancelsTheOldOne() {
        // The tap missed the first swipe's `ended` (e.g. it was disabled by a timeout).
        let result = run([swipe(.began, -60, 0), swipe(.began, 60, 0)], probe: FakeProbe(window: window))
        #expect(
            result.updates == [
                .preview(context, .slot(.leftHalf)), .cancel, .preview(context, .slot(.rightHalf)),
            ])
    }

    @Test func newPinchAfterALostEndCancelsTheOldOne() {
        let result = run([pinch(.began, 0.3), pinch(.began, -0.3)], probe: FakeProbe(window: window))
        #expect(result.updates == [.preview(context, .slot(.fill)), .cancel, .preview(context, .restore)])
    }

    @Test func resetCancelsAGestureInProgressAndReturnsToIdle() {
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: FakeProbe(window: window)) { updates.append($0) }
        _ = recognizer.handle(swipe(.began, -60, 0))
        recognizer.reset()
        #expect(updates == [.preview(context, .slot(.leftHalf)), .cancel])
        #expect(recognizer.handle(swipe(.changed, -60, 0)) == .passThrough)
    }

    @Test func resetWhenIdleEmitsNothing() {
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: FakeProbe(window: window)) { updates.append($0) }
        recognizer.reset()
        #expect(updates.isEmpty)
    }
}
