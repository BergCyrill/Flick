/// Remembers, per window, the frame it had before Flick last moved it.
public struct FrameHistory {
    private var frames: [WindowHandle: GlobalRect] = [:]

    public init() {}

    public mutating func record(_ frame: GlobalRect, for window: WindowHandle) {
        frames[window] = frame
    }

    public func peek(for window: WindowHandle) -> GlobalRect? {
        frames[window]
    }

    public mutating func take(for window: WindowHandle) -> GlobalRect? {
        frames.removeValue(forKey: window)
    }
}
