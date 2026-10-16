/// Recognizes scrolling while the right button is held on a titlebar and turns it into fill and
/// restore updates, committed on release. The press is swallowed so the app shows no menu; a
/// release without any scroll asks for the click to be replayed.
@MainActor
public final class HoldScrollRecognizer {
    /// While paused, new presses are not claimed. A hold already claimed finishes.
    public var isPaused = false

    private enum State {
        case idle
        /// Not a claimed press: everything passes until the release.
        case ignored
        /// Titlebar press swallowed. `ladder` is how far scrolling has got.
        case holding(GestureContext, ladder: ScrollLadder, scrolled: Bool)
    }

    private let probe: TitlebarProbe
    private let settings: @MainActor () -> FlickSettings
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    /// - Parameter settings: read once per hold, at the press.
    public init(
        probe: TitlebarProbe,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() },
        onUpdate: @escaping (GestureUpdate) -> Void
    ) {
        self.probe = probe
        self.settings = settings
        self.onUpdate = onUpdate
    }

    /// Whether the right button is down as far as this recognizer knows.
    public var isTracking: Bool {
        if case .idle = state { return false }
        return true
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case let .rightMouseDown(location):
            // A press while a hold is tracked means its release was lost.
            reset()
            return press(at: location)
        case let .rightMouseDragged(location):
            return follow(location)
        case .rightMouseUp:
            return release()
        case let .holdScroll(deltaY, precise, inverted, _):
            return scroll(deltaY: deltaY, precise: precise, inverted: inverted)
        case .scroll, .momentum, .magnify, .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            return .passThrough
        }
    }

    /// Abandons a hold in progress, e.g. after the event tap was disabled and events were lost.
    /// Its press is dropped, not replayed.
    public func reset() {
        if case .holding = state {
            onUpdate(.cancel)
        }
        state = .idle
    }

    private func press(at location: GlobalPoint) -> EventDecision {
        guard !isPaused, settings().scrollButton.includesRight,
            let window = probe.window(atTitlebar: location)
        else {
            state = .ignored
            return .passThrough
        }
        let context = GestureContext(window: window, pointer: location)
        state = .holding(context, ladder: ScrollLadder(), scrolled: false)
        return .swallow
    }

    private func follow(_ location: GlobalPoint) -> EventDecision {
        guard case let .holding(context, ladder, scrolled) = state else { return .passThrough }
        let moved = GestureContext(window: context.window, pointer: location)
        state = .holding(moved, ladder: ladder, scrolled: scrolled)
        if let target = ladder.target {
            onUpdate(.preview(moved, target))
        }
        return .swallow
    }

    private func release() -> EventDecision {
        defer { state = .idle }
        guard case let .holding(context, ladder, scrolled) = state else { return .passThrough }
        if let target = ladder.target {
            onUpdate(.commit(context, target))
            return .swallow
        }
        if scrolled {
            onUpdate(.cancel)
            return .swallow
        }
        return .replayPress
    }

    private func scroll(deltaY: Double, precise: Bool, inverted: Bool) -> EventDecision {
        guard case .holding(let context, var ladder, _) = state else { return .passThrough }
        let oldTarget = ladder.target
        ladder.scroll(deltaY: deltaY, precise: precise, invertedFromDevice: inverted)
        state = .holding(context, ladder: ladder, scrolled: true)
        if ladder.target != oldTarget {
            onUpdate(.preview(context, ladder.target))
        }
        return .swallow
    }
}
