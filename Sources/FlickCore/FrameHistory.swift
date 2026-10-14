/// Remembers, per window, the frame to restore: the one it had before the first snap of a run.
/// A run continues while the window stays where Flick placed it, and ends when it is moved by
/// hand or restored.
public struct FrameHistory {
    /// Frames whose edges differ by at most this many points count as "where Flick placed it".
    public static let tolerance: Double = 2

    private struct Entry {
        var original: GlobalRect
        var placed: GlobalRect
    }

    private var entries: [WindowHandle: Entry] = [:]

    public init() {}

    /// Records that Flick moved `window` from `current` to `placed` (the frame read back after the
    /// move, including any adjustment the app made).
    public mutating func recordMove(from current: GlobalRect, to placed: GlobalRect, for window: WindowHandle) {
        if let entry = entries[window], Self.isClose(entry.placed, current) {
            entries[window]?.placed = placed
        } else {
            entries[window] = Entry(original: current, placed: placed)
        }
    }

    public func peek(for window: WindowHandle) -> GlobalRect? {
        entries[window]?.original
    }

    public mutating func take(for window: WindowHandle) -> GlobalRect? {
        entries.removeValue(forKey: window)?.original
    }

    private static func isClose(_ lhs: GlobalRect, _ rhs: GlobalRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}
