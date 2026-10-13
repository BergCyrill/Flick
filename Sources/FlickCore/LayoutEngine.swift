/// Turns a slot into a window frame inside a screen's visible frame.
public enum LayoutEngine {
    /// Gap in points between slots and against the visible-frame edges.
    public static let defaultGap: Double = 8

    public static func frame(for slot: Slot, in visible: GlobalRect, gap: Double = defaultGap) -> GlobalRect {
        let fullWidth = (visible.width - 2 * gap).rounded(.down)
        let fullHeight = (visible.height - 2 * gap).rounded(.down)
        let halfWidth = ((visible.width - 3 * gap) / 2).rounded(.down)
        let halfHeight = ((visible.height - 3 * gap) / 2).rounded(.down)

        let left = (visible.minX + gap).rounded()
        let top = (visible.minY + gap).rounded()
        // Right column and bottom row are anchored to the far edges so the outer gap stays exact.
        let right = (visible.maxX - gap).rounded() - halfWidth
        let bottom = (visible.maxY - gap).rounded() - halfHeight

        switch slot {
        case .leftHalf: return GlobalRect(x: left, y: top, width: halfWidth, height: fullHeight)
        case .rightHalf: return GlobalRect(x: right, y: top, width: halfWidth, height: fullHeight)
        case .topHalf: return GlobalRect(x: left, y: top, width: fullWidth, height: halfHeight)
        case .bottomHalf: return GlobalRect(x: left, y: bottom, width: fullWidth, height: halfHeight)
        case .topLeft: return GlobalRect(x: left, y: top, width: halfWidth, height: halfHeight)
        case .topRight: return GlobalRect(x: right, y: top, width: halfWidth, height: halfHeight)
        case .bottomLeft: return GlobalRect(x: left, y: bottom, width: halfWidth, height: halfHeight)
        case .bottomRight: return GlobalRect(x: right, y: bottom, width: halfWidth, height: halfHeight)
        case .fill: return GlobalRect(x: left, y: top, width: fullWidth, height: fullHeight)
        }
    }
}
