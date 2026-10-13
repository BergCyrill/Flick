/// The part of a window where Flick gestures may start.
public enum TitlebarZone {
    /// Height of the zone below the window's top edge, in points (titlebar plus unified toolbar).
    public static let height: Double = 40

    /// Fullscreen windows have no titlebar zone: their top edge belongs to the app's content.
    public static func contains(_ point: GlobalPoint, windowFrame: GlobalRect, isFullScreen: Bool) -> Bool {
        guard !isFullScreen else { return false }
        let zone = GlobalRect(
            x: windowFrame.x, y: windowFrame.y, width: windowFrame.width, height: min(height, windowFrame.height))
        return zone.contains(point)
    }
}
