/// A point in Flick's global coordinate space: origin at the top-left corner of the
/// primary display, y grows downwards. CGEvent locations and Accessibility frames use it.
public struct GlobalPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// An axis-aligned rectangle in Flick's global (top-left origin) coordinate space.
public struct GlobalRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }

    /// Half-open containment: the left and top edges are inside, the right and bottom are not.
    public func contains(_ point: GlobalPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// Mirrors the rect between AppKit's bottom-left-origin space (NSScreen, NSWindow) and
    /// Flick's top-left-origin space. Applying it twice returns the original rect.
    /// - Parameter primaryHeight: height of the primary display (`NSScreen.screens[0]`).
    public func flipped(primaryHeight: Double) -> GlobalRect {
        GlobalRect(x: x, y: primaryHeight - y - height, width: width, height: height)
    }
}
