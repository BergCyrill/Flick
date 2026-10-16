import Testing

@testable import FlickCore

@MainActor
@Suite struct HoldScrollRecognizerTests {
    let window = WindowHandle("finder-1")
    /// On the window's titlebar.
    let press = GlobalPoint(x: 400, y: 210)
    let later = GlobalPoint(x: 600, y: 400)
    static let right: FlickSettings = {
        var settings = FlickSettings()
        settings.scrollButton = .right
        return settings
    }()

    var context: GestureContext { GestureContext(window: window, pointer: press) }

    /// Classic scrolling mouse wheel: rolling it away from you gives positive deltas.
    func wheel(_ lines: Double) -> InputEvent {
        .holdScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: press)
    }

    func run(
        _ events: [InputEvent], probe: FakeProbe? = nil, settings: FlickSettings = HoldScrollRecognizerTests.right
    ) -> (decisions: [EventDecision], updates: [GestureUpdate]) {
        var updates: [GestureUpdate] = []
        let recognizer = HoldScrollRecognizer(
            probe: probe ?? FakeProbe(window: window), settings: { settings }, onUpdate: { updates.append($0) })
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    func settings(_ button: ScrollButton) -> FlickSettings {
        var settings = FlickSettings()
        settings.scrollButton = button
        return settings
    }

    @Test func scrollingAwayWhileHoldingPreviewsFillAndReleaseCommitsIt() {
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)])
        #expect(result.decisions == [.swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func scrollingTowardsYouTargetsRestore() {
        let result = run([.rightMouseDown(location: press), wheel(-1), .rightMouseUp(location: press)])
        #expect(result.updates == [.preview(context, .restore), .commit(context, .restore)])
    }

    @Test func naturalScrollingGivesTheSameDirection() {
        let away = InputEvent.holdScroll(deltaY: -1, precise: false, invertedFromDevice: true, location: press)
        let result = run([.rightMouseDown(location: press), away])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func aTrackpadNeedsTwentyPoints() {
        // Natural scrolling trackpad: fingers moving away give negative deltas.
        func fingers(_ points: Double) -> InputEvent {
            .holdScroll(deltaY: -points, precise: true, invertedFromDevice: true, location: press)
        }
        let result = run([.rightMouseDown(location: press), fingers(15), fingers(5)])
        #expect(result.decisions == [.swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func releaseWithoutScrollingAsksForAReplay() {
        let result = run([.rightMouseDown(location: press), .rightMouseUp(location: press)])
        #expect(result.decisions == [.swallow, .replayPress])
        #expect(result.updates.isEmpty)
    }

    @Test func movingWithoutScrollingStillAsksForAReplay() {
        let result = run([
            .rightMouseDown(location: press), .rightMouseDragged(location: later), .rightMouseUp(location: later),
        ])
        #expect(result.decisions == [.swallow, .swallow, .replayPress])
        #expect(result.updates.isEmpty)
    }

    @Test func scrollingFurtherCyclesThroughTheSlotsAndReleaseCommitsTheLast() {
        let result = run([.rightMouseDown(location: press), wheel(1), wheel(1), .rightMouseUp(location: press)])
        #expect(
            result.updates == [
                .preview(context, .slot(.fill)), .preview(context, .slot(.leftHalf)),
                .commit(context, .slot(.leftHalf)),
            ])
    }

    @Test func scrollingBackToNeutralCancelsWithoutAReplay() {
        let result = run([.rightMouseDown(location: press), wheel(1), wheel(-1), .rightMouseUp(location: press)])
        #expect(result.decisions == [.swallow, .swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(context, nil), .cancel])
    }

    @Test func aPressOffEveryTitlebarIsNotClaimed() {
        let probe = FakeProbe(window: nil)
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)], probe: probe)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints == [press])
    }

    @Test func offClaimsNothing() {
        let probe = FakeProbe(window: window)
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, probe: probe, settings: settings(.off))
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func leftOnlyClaimsNothing() {
        let probe = FakeProbe(window: window)
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, probe: probe, settings: settings(.left))
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func bothClaims() {
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, settings: settings(.both))
        #expect(result.decisions == [.swallow, .swallow, .swallow])
    }

    @Test func pausedClaimsNothing() {
        var updates: [GestureUpdate] = []
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { Self.right }, onUpdate: { updates.append($0) })
        recognizer.isPaused = true
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        #expect(events.map { recognizer.handle($0) } == [.passThrough, .passThrough, .passThrough])
        #expect(updates.isEmpty)
    }

    @Test func settingsAreReadOncePerHold() {
        let box = SettingsBox()
        box.settings.scrollButton = .right
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { box.read() }, onUpdate: { _ in })
        let events: [InputEvent] = [
            .rightMouseDown(location: press), wheel(1), wheel(1), wheel(-1), .rightMouseUp(location: press),
        ]
        _ = events.map { recognizer.handle($0) }
        #expect(box.reads == 1)
    }

    @Test func thePreviewFollowsThePointer() {
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseDragged(location: later)])
        let moved = GestureContext(window: window, pointer: later)
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(moved, .slot(.fill))])
    }

    @Test func eventsWithoutAPressPassThrough() {
        let probe = FakeProbe(window: window)
        let events: [InputEvent] = [.rightMouseDragged(location: later), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, probe: probe)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func theNextPressCancelsAHoldWhoseReleaseWasLost() {
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseDown(location: press)])
        #expect(result.decisions == [.swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func resetCancelsAHoldAndItsReleasePassesThrough() {
        var updates: [GestureUpdate] = []
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { Self.right }, onUpdate: { updates.append($0) })
        _ = recognizer.handle(.rightMouseDown(location: press))
        _ = recognizer.handle(wheel(1))
        recognizer.reset()
        #expect(recognizer.handle(.rightMouseUp(location: press)) == .passThrough)
        #expect(updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func otherEventsPassThroughWhileHolding() {
        let result = run([
            .rightMouseDown(location: press),
            .scroll(phase: .began, deltaX: -60, deltaY: 0, invertedFromDevice: true, location: press),
            .momentum(phase: .changed),
            .magnify(phase: .began, magnification: 0.3, location: press),
            .mouseDown(location: press),
            .dragScroll(deltaY: 1, precise: false, invertedFromDevice: false, location: press),
            .mouseUp(location: press),
        ])
        #expect(result.decisions == [.swallow] + Array(repeating: .passThrough, count: 6))
        #expect(result.updates.isEmpty)
    }

    @Test func tracksFromPressToRelease() {
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { Self.right }, onUpdate: { _ in })
        #expect(!recognizer.isTracking)
        _ = recognizer.handle(.rightMouseDown(location: press))
        #expect(recognizer.isTracking)
        _ = recognizer.handle(.rightMouseUp(location: press))
        #expect(!recognizer.isTracking)
    }
}

@MainActor
@Suite struct RightButtonInOtherRecognizersTests {
    @Test func rightButtonEventsPassThroughTheTrackpadAndDragRecognizers() {
        let point = GlobalPoint(x: 400, y: 210)
        let probe = FakeProbe(window: WindowHandle("w"))
        var updates: [GestureUpdate] = []
        let gestures = GestureRecognizer(probe: probe) { updates.append($0) }
        let drags = DragScrollRecognizer(probe: probe, windows: FakeWindows()) { updates.append($0) }
        let events: [InputEvent] = [
            .rightMouseDown(location: point), .rightMouseDragged(location: point),
            .holdScroll(deltaY: 1, precise: false, invertedFromDevice: false, location: point),
            .rightMouseUp(location: point),
        ]
        #expect(events.map { gestures.handle($0) } == Array(repeating: .passThrough, count: 4))
        #expect(events.map { drags.handle($0) } == Array(repeating: .passThrough, count: 4))
        #expect(updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }
}
