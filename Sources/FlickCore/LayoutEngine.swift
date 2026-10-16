/// Turns a slot into a window frame inside a screen's visible frame.
public enum LayoutEngine {
    /// Gap in points between slots and against the visible-frame edges.
    public static let defaultGap: Double = 8

    /// The gap that matches macOS's own tiling: *Tiled windows have margins* in Desktop & Dock.
    /// Unset counts as off, as on a fresh install.
    public static func gap(tiledWindowMargins: Bool?) -> Double {
        tiledWindowMargins == true ? defaultGap : 0
    }

    public static func frame(for slot: Slot, in visible: GlobalRect, gap: Double = defaultGap) -> GlobalRect {
        let fullWidth = (visible.width - 2 * gap).rounded(.down)
        let fullHeight = (visible.height - 2 * gap).rounded(.down)
        let halfWidth = ((visible.width - 3 * gap) / 2).rounded(.down)
        let halfHeight = ((visible.height - 3 * gap) / 2).rounded(.down)

        let left = (visible.minX + gap).rounded()
        let top = (visible.minY + gap).rounded()
        // Right column and bottom row take the point left over by rounding, so both the outer
        // gap and the gap between neighbours stay exact.
        let right = left + halfWidth + gap
        let bottom = top + halfHeight + gap
        let rightWidth = (visible.maxX - gap).rounded() - right
        let bottomHeight = (visible.maxY - gap).rounded() - bottom

        switch slot {
        case .leftHalf: return GlobalRect(x: left, y: top, width: halfWidth, height: fullHeight)
        case .rightHalf: return GlobalRect(x: right, y: top, width: rightWidth, height: fullHeight)
        case .topHalf: return GlobalRect(x: left, y: top, width: fullWidth, height: halfHeight)
        case .bottomHalf: return GlobalRect(x: left, y: bottom, width: fullWidth, height: bottomHeight)
        case .topLeft: return GlobalRect(x: left, y: top, width: halfWidth, height: halfHeight)
        case .topRight: return GlobalRect(x: right, y: top, width: rightWidth, height: halfHeight)
        case .bottomLeft: return GlobalRect(x: left, y: bottom, width: halfWidth, height: bottomHeight)
        case .bottomRight: return GlobalRect(x: right, y: bottom, width: rightWidth, height: bottomHeight)
        case .fill: return GlobalRect(x: left, y: top, width: fullWidth, height: fullHeight)
        }
    }
}
