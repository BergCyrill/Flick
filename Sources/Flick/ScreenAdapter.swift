import AppKit
import FlickCore

/// Screen geometry from NSScreen, converted to Flick's top-left coordinates.
@MainActor
final class ScreenAdapter: ScreenProvider {
    static var primaryHeight: Double {
        Double(NSScreen.screens.first?.frame.height ?? 0)
    }

    func visibleFrame(containing point: GlobalPoint) -> GlobalRect? {
        let height = Self.primaryHeight
        for screen in NSScreen.screens where GlobalRect(screen.frame).flipped(primaryHeight: height).contains(point) {
            return GlobalRect(screen.visibleFrame).flipped(primaryHeight: height)
        }
        return nil
    }

    /// *Tiled windows have margins* from System Settings → Desktop & Dock, read fresh each time
    /// so a change applies to the next snap. `nil` until the switch has been touched.
    static var tiledWindowMargins: Bool? {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("EnableTiledWindowMargins" as CFString, domain) as? Bool
    }
}

extension GlobalRect {
    init(_ rect: NSRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}
