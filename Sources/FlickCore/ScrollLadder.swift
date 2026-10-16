/// Turns scrolling while a mouse button is held into a target: one step towards you restores,
/// away from you steps through the slots, from fill onwards. Scrolling back to the start cancels.
public struct ScrollLadder: Equatable, Sendable {
    /// The slots in the order scrolling away reaches them.
    public static let slots: [Slot] = [
        .fill, .leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .topHalf, .bottomHalf,
    ]
    /// Trackpads and Magic Mouse report points: the first step takes this far, as before slots
    /// cycled, and every further one `preciseStep`.
    public static let preciseFirstStep: Double = 20
    public static let preciseStep: Double = 40

    /// Away from you counts positive: notches for a mouse wheel, points otherwise.
    private var amount: Double = 0
    private var precise = false

    public init() {}

    public var target: Target? {
        let step = self.step
        if step < 0 { return .restore }
        if step == 0 { return nil }
        return .slot(Self.slots[step - 1])
    }

    public mutating func scroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool) {
        let finger = DirectionClassifier.fingerDelta(
            scrollingDeltaX: 0, scrollingDeltaY: deltaY, invertedFromDevice: invertedFromDevice)
        // Fingers or wheel moving away from you is "up", a negative dy.
        let away = -finger.dy
        self.precise = precise
        // A fast spin reports several lines per notch; each notch is still one step.
        let change = precise ? away : (away > 0 ? 1 : away < 0 ? -1 : 0)
        // Clamped to the ends, so scrolling back past them takes effect at once.
        amount = min(max(amount + change, lowest), highest)
    }

    private var lowest: Double {
        precise ? -Self.preciseFirstStep : -1
    }

    private var highest: Double {
        let last = Double(Self.slots.count - 1)
        return precise ? Self.preciseFirstStep + Self.preciseStep * last : last + 1
    }

    /// -1 is restore, 0 the start, 1 and up the slots.
    private var step: Int {
        guard precise else { return Int(amount) }
        if amount <= -Self.preciseFirstStep { return -1 }
        if amount < Self.preciseFirstStep { return 0 }
        return 1 + Int((amount - Self.preciseFirstStep) / Self.preciseStep)
    }
}
