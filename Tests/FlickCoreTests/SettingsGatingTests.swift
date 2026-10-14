import Testing

@testable import FlickCore

/// Settings that a test changes while a recognizer holds a closure reading them.
@MainActor
final class SettingsBox {
    var settings = FlickSettings()
    private(set) var reads = 0

    func read() -> FlickSettings {
        reads += 1
        return settings
    }
}

@MainActor
@Suite struct SettingsGatingTests {
    let window = WindowHandle("finder-1")
    let start = GlobalPoint(x: 600, y: 260)
    var context: GestureContext { GestureContext(window: window, pointer: start) }

    /// Natural scrolling: the deltas follow the fingers.
    func swipe(_ phase: GesturePhase, _ dx: Double = 0) -> InputEvent {
        .scroll(phase: phase, deltaX: dx, deltaY: 0, invertedFromDevice: true, location: start)
    }

    func pinch(_ phase: GesturePhase, _ magnification: Double = 0) -> InputEvent {
        .magnify(phase: phase, magnification: magnification, location: start)
    }

    func run(_ events: [InputEvent], probe: FakeProbe, settings: FlickSettings)
        -> (decisions: [EventDecision], updates: [GestureUpdate])
    {
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: probe, settings: { settings }, onUpdate: { updates.append($0) })
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    @Test func swipeIsNotClaimedWhenSwipeToSnapIsOff() {
        var settings = FlickSettings()
        settings.swipeToSnap = false
        let probe = FakeProbe(window: window)
        let result = run([swipe(.began, -60), swipe(.ended)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func pinchStillWorksWhenOnlySwipeIsOff() {
        var settings = FlickSettings()
        settings.swipeToSnap = false
        let result = run([pinch(.began, 0.3), pinch(.ended)], probe: FakeProbe(window: window), settings: settings)
        #expect(result.decisions == [.swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func pinchIsNotClaimedWhenPinchIsOff() {
        var settings = FlickSettings()
        settings.pinchToFillRestore = false
        let probe = FakeProbe(window: window)
        let result = run([pinch(.began, 0.3), pinch(.ended)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func swipeStillWorksWhenOnlyPinchIsOff() {
        var settings = FlickSettings()
        settings.pinchToFillRestore = false
        let result = run([swipe(.began, -60), swipe(.ended)], probe: FakeProbe(window: window), settings: settings)
        #expect(result.decisions == [.swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.leftHalf)), .commit(context, .slot(.leftHalf))])
    }

    @Test func aGestureInProgressFinishesUnderTheSettingsItStartedWith() {
        let box = SettingsBox()
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(
            probe: FakeProbe(window: window), settings: { box.settings }, onUpdate: { updates.append($0) })
        _ = recognizer.handle(swipe(.began, -60))
        box.settings.swipeToSnap = false
        let decisions = [swipe(.changed, -5), swipe(.ended)].map { recognizer.handle($0) }
        #expect(decisions == [.swallow, .swallow])
        #expect(updates.last == .commit(context, .slot(.leftHalf)))
    }
}

@MainActor
@Suite struct PreviewSettingTests {
    let window = WindowHandle("w")
    let windows = FakeWindows()
    let preview = FakePreview()
    var context: GestureContext { GestureContext(window: window, pointer: GlobalPoint(x: 400, y: 210)) }

    func makeController(livePreview: Bool) -> FlickController {
        windows.frames[window] = GlobalRect(x: 300, y: 200, width: 640, height: 480)
        var settings = FlickSettings()
        settings.livePreview = livePreview
        return FlickController(windows: windows, screens: FakeScreens(), preview: preview, settings: { settings })
    }

    @Test func previewOffOnlyHides() {
        let controller = makeController(livePreview: false)
        controller.handle(.preview(context, .slot(.leftHalf)))
        #expect(preview.shown == nil)
        #expect(preview.hideCount == 1)
    }

    @Test func previewOffStillMovesTheWindowOnCommit() {
        let controller = makeController(livePreview: false)
        controller.handle(.commit(context, .slot(.rightHalf)))
        #expect(windows.frames[window] == GlobalRect(x: 724, y: 33, width: 708, height: 859))
    }
}
