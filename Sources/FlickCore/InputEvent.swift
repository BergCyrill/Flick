/// Phase of a trackpad gesture, mirroring `NSEvent.Phase`.
public enum GesturePhase: Equatable, Sendable {
    case mayBegin, began, changed, ended, cancelled
}

/// A trackpad event, already translated from CGEvent/NSEvent by the adapter layer.
public enum InputEvent: Equatable, Sendable {
    /// Two-finger scrolling while the fingers are on the trackpad. Deltas are the raw
    /// `NSEvent.scrollingDeltaX/Y` values.
    case scroll(phase: GesturePhase, deltaX: Double, deltaY: Double, invertedFromDevice: Bool, location: GlobalPoint)
    /// Inertia scrolling after the fingers lifted.
    case momentum(phase: GesturePhase)
    /// Pinch. `magnification` is the delta since the previous event.
    case magnify(phase: GesturePhase, magnification: Double, location: GlobalPoint)
}

/// What the event tap should do with an event.
public enum EventDecision: Equatable, Sendable {
    case passThrough
    case swallow
}
