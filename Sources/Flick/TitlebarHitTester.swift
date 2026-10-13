import ApplicationServices
import FlickCore
import Foundation

/// Finds the standard window whose titlebar zone (top 40 pt) is under a point.
@MainActor
final class TitlebarHitTester: TitlebarProbe {
    private let systemWide = AXUIElementCreateSystemWide()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func window(atTitlebar point: GlobalPoint) -> WindowHandle? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
            let hit
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid != ownPID,
            let window = Self.window(containing: hit),
            Accessibility.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
            let frame = Accessibility.frame(of: window)
        else { return nil }

        let isFullScreen = Accessibility.bool(window, "AXFullScreen") ?? false
        return TitlebarZone.contains(point, windowFrame: frame, isFullScreen: isFullScreen) ? WindowHandle(window) : nil
    }

    private static func window(containing element: AXUIElement) -> AXUIElement? {
        if Accessibility.string(element, kAXRoleAttribute) == kAXWindowRole {
            return element
        }
        if let window = Accessibility.element(element, kAXWindowAttribute) {
            return window
        }
        var current = element
        for _ in 0..<32 {
            guard let parent = Accessibility.element(current, kAXParentAttribute) else { return nil }
            if Accessibility.string(parent, kAXRoleAttribute) == kAXWindowRole {
                return parent
            }
            current = parent
        }
        return nil
    }
}
