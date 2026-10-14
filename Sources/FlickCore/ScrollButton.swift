/// Which mouse button scroll to fill and restore listens to: the left one while a window is
/// dragged, the right one while it is held on a titlebar.
public enum ScrollButton: String, CaseIterable, Equatable, Sendable {
    case off, left, right, both

    public var includesLeft: Bool { self == .left || self == .both }
    public var includesRight: Bool { self == .right || self == .both }
}
