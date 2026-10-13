import ApplicationServices
import FlickCore
import os

/// Reads and sets window frames through Accessibility.
@MainActor
final class WindowMover: WindowAccess {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "WindowMover")
    /// Moves run outside the event tap, so slow-resizing apps may take longer than the global
    /// 0.25 s Accessibility timeout set by MenuBarApp.
    private static let moveTimeout: Float = 1

    func frame(of window: WindowHandle) -> GlobalRect? {
        Accessibility.frame(of: window.element)
    }

    func setFrame(_ frame: GlobalRect, of window: WindowHandle) -> Bool {
        let element = window.element
        AXUIElementSetMessagingTimeout(element, Self.moveTimeout)
        // Position, size, position: moving first lets a large window shrink on the target
        // screen; the second move fixes apps that clamp the origin while resizing.
        let moved = Accessibility.setPosition(element, x: frame.x, y: frame.y)
        Accessibility.setSize(element, width: frame.width, height: frame.height)
        Accessibility.setPosition(element, x: frame.x, y: frame.y)
        if !moved {
            Self.logger.warning("Could not move window: AXPosition was rejected")
        }
        return moved
    }
}
