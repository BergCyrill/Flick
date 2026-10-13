import Foundation

/// Maps a finger translation to one of the 8 swipe slots.
public enum DirectionClassifier {
    /// Below this distance (points) a swipe has no direction yet.
    public static let minimumDistance: Double = 40

    // Sector 0 is "right", then clockwise in screen orientation (y grows downwards).
    private static let sectors: [Slot] = [
        .rightHalf, .bottomRight, .bottomHalf, .bottomLeft,
        .leftHalf, .topLeft, .topHalf, .topRight,
    ]

    /// - Parameters:
    ///   - dx: finger movement to the right (negative = left), in points.
    ///   - dy: finger movement downwards (negative = up), in points.
    public static func slot(dx: Double, dy: Double, minimumDistance: Double = minimumDistance) -> Slot? {
        guard (dx * dx + dy * dy).squareRoot() >= minimumDistance else { return nil }
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let sector = Int(((degrees + 22.5) / 45).rounded(.down)) % 8
        return sectors[sector]
    }

    /// Converts AppKit scrolling deltas into finger movement in screen orientation.
    /// With natural scrolling (`invertedFromDevice == true`) the deltas already follow the
    /// fingers; with classic scrolling they point the opposite way.
    public static func fingerDelta(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        invertedFromDevice: Bool
    ) -> (dx: Double, dy: Double) {
        let sign: Double = invertedFromDevice ? 1 : -1
        return (sign * scrollingDeltaX, sign * scrollingDeltaY)
    }
}
