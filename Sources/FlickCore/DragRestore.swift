/// Where a window goes when it is restored during a drag: back to its restore size, under the
/// pointer, still held at the spot that was grabbed.
public enum DragRestore {
    /// - Parameters:
    ///   - original: the frame to restore. Only its size is used.
    ///   - drag: where the window was, and where it was grabbed, when the button went down.
    ///   - pointer: where the pointer is now.
    ///   - visible: visible frame of the screen under the pointer.
    public static func frame(
        restoring original: GlobalRect,
        drag: DragContext,
        pointer: GlobalPoint,
        visible: GlobalRect
    ) -> GlobalRect {
        let press = drag.frameAtPress
        let fraction = press.width > 0 ? (drag.pressPoint.x - press.x) / press.width : 0.5
        let top = min(drag.pressPoint.y - press.y, original.height)
        let x = pointer.x - fraction * original.width
        let y = pointer.y - top
        // Keep it inside `visible`; a window larger than `visible` aligns to its top-left corner.
        let clampedX = max(min(x, visible.maxX - original.width), visible.minX)
        let clampedY = max(min(y, visible.maxY - original.height), visible.minY)
        return GlobalRect(
            x: clampedX.rounded(), y: clampedY.rounded(), width: original.width, height: original.height)
    }
}
