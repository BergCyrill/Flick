import ApplicationServices
import FlickCore
import os

/// Reads and sets window frames through Accessibility.
@MainActor
final class WindowMover: WindowAccess {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "WindowMover")

    func frame(of window: WindowHandle) -> GlobalRect? {
        Accessibility.frame(of: window.element)
    }

    func setFrame(_ frame: GlobalRect, of window: WindowHandle) -> Bool {
        let element = window.element
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
