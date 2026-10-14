/// Phase of a trackpad gesture, mirroring `NSEvent.Phase`.
public enum GesturePhase: Equatable, Sendable {
    case mayBegin, began, changed, ended, cancelled
}

/// A trackpad or mouse event, already translated from CGEvent/NSEvent by the adapter layer.
public enum InputEvent: Equatable, Sendable {
    /// Two-finger scrolling while the fingers are on the trackpad. Deltas are the raw
    /// `NSEvent.scrollingDeltaX/Y` values.
    case scroll(phase: GesturePhase, deltaX: Double, deltaY: Double, invertedFromDevice: Bool, location: GlobalPoint)
    /// Inertia scrolling after the fingers lifted.
    case momentum(phase: GesturePhase)
    /// Pinch. `magnification` is the delta since the previous event.
    case magnify(phase: GesturePhase, magnification: Double, location: GlobalPoint)
    /// Left mouse button pressed, moved while pressed, released. Only observed, never swallowed.
    case mouseDown(location: GlobalPoint)
    case mouseDragged(location: GlobalPoint)
    case mouseUp(location: GlobalPoint)
    /// A scroll while the left mouse button is held, momentum excluded. `deltaY` is the raw
    /// `NSEvent.scrollingDeltaY`: lines for a mouse wheel (`precise == false`), points for a
    /// trackpad.
    case dragScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)
    /// Right mouse button pressed, moved while pressed, released. Swallowed only for a press on a
    /// titlebar while hold + scroll is on.
    case rightMouseDown(location: GlobalPoint)
    case rightMouseDragged(location: GlobalPoint)
    case rightMouseUp(location: GlobalPoint)
    /// A scroll while the right (and not the left) mouse button is held, momentum excluded.
    /// Deltas as for `dragScroll`.
    case holdScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)
}

/// What the event tap should do with an event.
public enum EventDecision: Equatable, Sendable {
    case passThrough
    case swallow
    /// For a release: swallow it, then post the swallowed press and this release again, in that
    /// order, so the app gets its click after all.
    case replayPress
}
