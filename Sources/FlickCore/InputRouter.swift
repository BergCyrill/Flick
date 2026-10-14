/// The event tap's single entry point: hands each event to the recognizer it belongs to.
@MainActor
public final class InputRouter {
    private let gestures: GestureRecognizer
    private let dragScroll: DragScrollRecognizer

    public init(gestures: GestureRecognizer, dragScroll: DragScrollRecognizer) {
        self.gestures = gestures
        self.dragScroll = dragScroll
    }

    /// Pauses or resumes both recognizers.
    public var isPaused: Bool {
        get { gestures.isPaused }
        set {
            gestures.isPaused = newValue
            dragScroll.isPaused = newValue
        }
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            return dragScroll.handle(event)
        case .scroll:
            // A trackpad scroll without the button held: a drag we track ended unseen.
            if dragScroll.isTracking {
                dragScroll.reset()
            }
            return gestures.handle(event)
        case .momentum, .magnify:
            return gestures.handle(event)
        }
    }

    /// Abandons whatever is in progress, e.g. after the event tap was disabled.
    public func reset() {
        gestures.reset()
        dragScroll.reset()
    }
}
