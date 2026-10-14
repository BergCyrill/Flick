/// Finds the window whose titlebar is under a point.
@MainActor
public protocol TitlebarProbe: AnyObject {
    func window(atTitlebar point: GlobalPoint) -> WindowHandle?
}

/// Where a dragged window was, and where it was grabbed, when the mouse button went down.
public struct DragContext: Equatable, Sendable {
    public let frameAtPress: GlobalRect
    public let pressPoint: GlobalPoint

    public init(frameAtPress: GlobalRect, pressPoint: GlobalPoint) {
        self.frameAtPress = frameAtPress
        self.pressPoint = pressPoint
    }
}

/// The window a claimed gesture acts on, and where the pointer is: where a trackpad gesture
/// started, or where the pointer is now during a drag.
public struct GestureContext: Equatable {
    public let window: WindowHandle
    public let pointer: GlobalPoint
    /// Set for drag + scroll, `nil` for trackpad gestures.
    public let drag: DragContext?

    public init(window: WindowHandle, pointer: GlobalPoint, drag: DragContext? = nil) {
        self.window = window
        self.pointer = pointer
        self.drag = drag
    }
}

public enum GestureUpdate: Equatable {
    /// The target changed while the fingers are still down. `nil` means "no target right now".
    case preview(GestureContext, Target?)
    /// The fingers lifted with a target.
    case commit(GestureContext, Target)
    /// The gesture ended without a target, or the system cancelled it.
    case cancel
}

/// Decides which trackpad gestures belong to Flick and turns them into `GestureUpdate`s.
@MainActor
public final class GestureRecognizer {
    /// Cumulative magnification needed before a pinch has a target.
    public static let pinchThreshold = 0.15

    /// While paused, new gestures are not claimed. A gesture already in progress finishes.
    public var isPaused = false

    private enum State {
        case idle
        case swiping(GestureContext, dx: Double, dy: Double, target: Target?)
        case pinching(GestureContext, scale: Double, target: Target?)
        case swallowingMomentum
    }

    private let probe: TitlebarProbe
    private let settings: @MainActor () -> FlickSettings
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    /// - Parameter settings: read once when a gesture begins.
    public init(
        probe: TitlebarProbe,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() },
        onUpdate: @escaping (GestureUpdate) -> Void
    ) {
        self.probe = probe
        self.settings = settings
        self.onUpdate = onUpdate
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case let .scroll(phase, deltaX, deltaY, inverted, location):
            let finger = DirectionClassifier.fingerDelta(
                scrollingDeltaX: deltaX, scrollingDeltaY: deltaY, invertedFromDevice: inverted)
            return handleScroll(phase: phase, dx: finger.dx, dy: finger.dy, location: location)
        case let .momentum(phase):
            return handleMomentum(phase: phase)
        case let .magnify(phase, magnification, location):
            return handleMagnify(phase: phase, magnification: magnification, location: location)
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll,
            .rightMouseDown, .rightMouseDragged, .rightMouseUp, .holdScroll:
            // Drag + scroll and hold + scroll belong to their own recognizers.
            return .passThrough
        }
    }

    /// Abandons any gesture in progress, e.g. after the event tap was disabled and events were lost.
    public func reset() {
        cancelGestureInProgress()
        state = .idle
    }

    private func handleScroll(phase: GesturePhase, dx: Double, dy: Double, location: GlobalPoint) -> EventDecision {
        switch (state, phase) {
        case (.pinching, _), (_, .mayBegin):
            return .passThrough
        case (_, .began):
            cancelGestureInProgress()
            guard let context = claim(at: location, enabled: settings().swipeToSnap) else {
                state = .idle
                return .passThrough
            }
            state = .swiping(context, dx: 0, dy: 0, target: nil)
            return accumulateSwipe(dx: dx, dy: dy)
        case (.swiping, .changed):
            return accumulateSwipe(dx: dx, dy: dy)
        case let (.swiping(context, _, _, target), .ended):
            finish(context, target: target)
            state = .swallowingMomentum
            return .swallow
        case (.swiping, .cancelled):
            onUpdate(.cancel)
            state = .idle
            return .swallow
        default:
            return .passThrough
        }
    }

    private func accumulateSwipe(dx: Double, dy: Double) -> EventDecision {
        guard case let .swiping(context, oldX, oldY, oldTarget) = state else { return .passThrough }
        let newX = oldX + dx
        let newY = oldY + dy
        let target = DirectionClassifier.slot(dx: newX, dy: newY).map(Target.slot)
        state = .swiping(context, dx: newX, dy: newY, target: target)
        if target != oldTarget {
            onUpdate(.preview(context, target))
        }
        return .swallow
    }

    private func handleMomentum(phase: GesturePhase) -> EventDecision {
        guard case .swallowingMomentum = state else { return .passThrough }
        if phase == .ended || phase == .cancelled {
            state = .idle
        }
        return .swallow
    }

    private func handleMagnify(phase: GesturePhase, magnification: Double, location: GlobalPoint) -> EventDecision {
        switch (state, phase) {
        case (.swiping, _), (_, .mayBegin):
            return .passThrough
        case (_, .began):
            cancelGestureInProgress()
            guard let context = claim(at: location, enabled: settings().pinchToFillRestore) else {
                state = .idle
                return .passThrough
            }
            state = .pinching(context, scale: 0, target: nil)
            return accumulatePinch(magnification)
        case (.pinching, .changed):
            return accumulatePinch(magnification)
        case let (.pinching(context, _, target), .ended):
            finish(context, target: target)
            state = .idle
            return .swallow
        case (.pinching, .cancelled):
            onUpdate(.cancel)
            state = .idle
            return .swallow
        default:
            return .passThrough
        }
    }

    private func accumulatePinch(_ magnification: Double) -> EventDecision {
        guard case let .pinching(context, oldScale, oldTarget) = state else { return .passThrough }
        let scale = oldScale + magnification
        let target: Target?
        if scale > Self.pinchThreshold {
            target = .slot(.fill)
        } else if scale < -Self.pinchThreshold {
            target = .restore
        } else {
            target = nil
        }
        state = .pinching(context, scale: scale, target: target)
        if target != oldTarget {
            onUpdate(.preview(context, target))
        }
        return .swallow
    }

    /// A gesture that is switched off in the settings, or paused, is never claimed: the probe
    /// isn't even asked, and all of its events pass through.
    private func claim(at location: GlobalPoint, enabled: Bool) -> GestureContext? {
        guard !isPaused, enabled, let window = probe.window(atTitlebar: location) else { return nil }
        return GestureContext(window: window, pointer: location)
    }

    private func finish(_ context: GestureContext, target: Target?) {
        if let target {
            onUpdate(.commit(context, target))
        } else {
            onUpdate(.cancel)
        }
    }

    /// A claimed gesture that never saw its `ended` must not leave its preview behind.
    private func cancelGestureInProgress() {
        switch state {
        case .swiping, .pinching:
            onUpdate(.cancel)
        case .idle, .swallowingMomentum:
            break
        }
    }
}
