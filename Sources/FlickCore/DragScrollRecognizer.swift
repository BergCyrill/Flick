/// Recognizes scrolling while a window is dragged by its titlebar and turns it into fill and
/// restore updates, committed on release. Mouse events are only observed, never swallowed.
@MainActor
public final class DragScrollRecognizer {
    /// While paused, new drags are not claimed. A drag already claimed finishes.
    public var isPaused = false

    private enum State {
        case idle
        /// Button down at this point, no scroll yet.
        case pressed(GlobalPoint)
        /// Not a titlebar drag: its scrolls go to the app until release.
        case ignored
        /// Titlebar drag: its scrolls are swallowed. `amount` counts away from you as positive.
        case claimed(GestureContext, amount: Double, target: Target?)
    }

    private let probe: TitlebarProbe
    private let windows: WindowAccess
    private let settings: @MainActor () -> FlickSettings
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    /// - Parameter settings: read once per drag, at its first scroll.
    public init(
        probe: TitlebarProbe,
        windows: WindowAccess,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() },
        onUpdate: @escaping (GestureUpdate) -> Void
    ) {
        self.probe = probe
        self.windows = windows
        self.settings = settings
        self.onUpdate = onUpdate
    }

    /// Whether the left button is down as far as this recognizer knows.
    public var isTracking: Bool {
        if case .idle = state { return false }
        return true
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case let .mouseDown(location):
            // A press while a drag is tracked means its release was lost.
            reset()
            state = .pressed(location)
        case let .mouseDragged(location):
            follow(location)
        case .mouseUp:
            release()
        case let .dragScroll(deltaY, precise, inverted, location):
            return scroll(deltaY: deltaY, precise: precise, inverted: inverted, location: location)
        case .scroll, .momentum, .magnify:
            break
        }
        return .passThrough
    }

    /// Abandons a drag in progress, e.g. after the event tap was disabled and events were lost.
    public func reset() {
        if case .claimed = state {
            onUpdate(.cancel)
        }
        state = .idle
    }

    private func follow(_ location: GlobalPoint) {
        guard case let .claimed(context, amount, target) = state else { return }
        let moved = GestureContext(window: context.window, pointer: location, drag: context.drag)
        state = .claimed(moved, amount: amount, target: target)
        if target != nil {
            onUpdate(.preview(moved, target))
        }
    }

    private func release() {
        if case let .claimed(context, _, target) = state {
            if let target {
                onUpdate(.commit(context, target))
            } else {
                onUpdate(.cancel)
            }
        }
        state = .idle
    }

    private func scroll(deltaY: Double, precise: Bool, inverted: Bool, location: GlobalPoint) -> EventDecision {
        switch state {
        case .idle, .ignored:
            return .passThrough
        case let .pressed(press):
            guard let context = claim(press: press, pointer: location) else {
                state = .ignored
                return .passThrough
            }
            state = .claimed(context, amount: 0, target: nil)
        case .claimed:
            break
        }
        accumulate(deltaY: deltaY, precise: precise, inverted: inverted)
        return .swallow
    }

    private func claim(press: GlobalPoint, pointer: GlobalPoint) -> GestureContext? {
        guard !isPaused, settings().scrollButton.includesLeft,
            let window = probe.window(atTitlebar: pointer),
            let current = windows.frame(of: window)
        else { return nil }
        // A dragged window moves with the pointer, so shifting it back gives its frame at the press.
        let frameAtPress = GlobalRect(
            x: current.x - (pointer.x - press.x), y: current.y - (pointer.y - press.y),
            width: current.width, height: current.height)
        return GestureContext(
            window: window, pointer: pointer, drag: DragContext(frameAtPress: frameAtPress, pressPoint: press))
    }

    private func accumulate(deltaY: Double, precise: Bool, inverted: Bool) {
        guard case let .claimed(context, oldAmount, oldTarget) = state else { return }
        let amount = oldAmount + ScrollTarget.step(deltaY: deltaY, invertedFromDevice: inverted)
        let target = ScrollTarget.target(amount: amount, precise: precise)
        state = .claimed(context, amount: amount, target: target)
        if target != oldTarget {
            onUpdate(.preview(context, target))
        }
    }
}
