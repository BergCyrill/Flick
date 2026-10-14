/// Turns scrolling while a mouse button is held into fill or restore: away from you fills,
/// towards you restores, once the amount passes the device's threshold.
public enum ScrollTarget {
    /// Mouse wheels report lines, trackpads report points.
    public static let wheelThreshold: Double = 1
    public static let preciseThreshold: Double = 20

    /// How far one scroll event moves the amount; away from you counts positive.
    public static func step(deltaY: Double, invertedFromDevice: Bool) -> Double {
        let finger = DirectionClassifier.fingerDelta(
            scrollingDeltaX: 0, scrollingDeltaY: deltaY, invertedFromDevice: invertedFromDevice)
        // Fingers or wheel moving away from you is "up", a negative dy.
        return -finger.dy
    }

    public static func target(amount: Double, precise: Bool) -> Target? {
        let threshold = precise ? preciseThreshold : wheelThreshold
        if amount >= threshold { return .slot(.fill) }
        if amount <= -threshold { return .restore }
        return nil
    }
}
