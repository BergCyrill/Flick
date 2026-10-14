/// The event tap's single entry point: hands each event to the recognizer it belongs to.
@MainActor
public final class InputRouter {
    private let gestures: GestureRecognizer
    private let dragScroll: DragScrollRecognizer
    private let holdScroll: HoldScrollRecognizer

    public init(gestures: GestureRecognizer, dragScroll: DragScrollRecognizer, holdScroll: HoldScrollRecognizer) {
        self.gestures = gestures
        self.dragScroll = dragScroll
        self.holdScroll = holdScroll
    }

    /// Pauses or resumes all three recognizers.
    public var isPaused: Bool {
        get { gestures.isPaused }
        set {
            gestures.isPaused = newValue
            dragScroll.isPaused = newValue
            holdScroll.isPaused = newValue
        }
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            return dragScroll.handle(event)
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp, .holdScroll:
            return holdScroll.handle(event)
        case .scroll(phase: .began, _, _, _, _):
            // A new trackpad gesture without a button held: a drag or hold we track ended unseen.
            // Other phases may be a scroll that was in flight when the button went up; its release
            // follows.
            if dragScroll.isTracking {
                dragScroll.reset()
            }
            if holdScroll.isTracking {
                holdScroll.reset()
            }
            return gestures.handle(event)
        case .scroll, .momentum, .magnify:
            return gestures.handle(event)
        }
    }

    /// Abandons whatever is in progress, e.g. after the event tap was disabled.
    public func reset() {
        gestures.reset()
        dragScroll.reset()
        holdScroll.reset()
    }
}
