/// A place on the 2×2 grid a window can snap to.
public enum Slot: CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case fill
}

/// What a gesture is aiming at.
public enum Target: Equatable, Sendable {
    case slot(Slot)
    case restore
}
