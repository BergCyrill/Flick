import Foundation

/// What the user turned on or off in the settings window. Launch at login isn't part of it:
/// macOS owns that state.
public struct FlickSettings: Equatable, Sendable {
    public var swipeToSnap = true
    public var pinchToFillRestore = true
    public var scrollButton = ScrollButton.left
    public var livePreview = true

    public init() {}

    /// Reads the settings from `defaults`. Keys that were never written keep their default.
    public init(defaults: UserDefaults) {
        for (key, path) in Self.keys {
            if let value = defaults.object(forKey: key) as? Bool {
                self[keyPath: path] = value
            }
        }
        if let name = defaults.string(forKey: Self.scrollButtonKey), let button = ScrollButton(rawValue: name) {
            scrollButton = button
        } else if let wasOn = defaults.object(forKey: Self.oldScrollKey) as? Bool {
            // Carried over from the switch the picker replaced.
            scrollButton = wasOn ? .left : .off
        }
    }

    public func save(to defaults: UserDefaults) {
        for (key, path) in Self.keys {
            defaults.set(self[keyPath: path], forKey: key)
        }
        defaults.set(scrollButton.rawValue, forKey: Self.scrollButtonKey)
    }

    private static let scrollButtonKey = "scrollButton"
    /// The switch that came before the picker: read once to carry its value over, never written.
    private static let oldScrollKey = "scrollWhileDragging"

    private static var keys: [(String, WritableKeyPath<FlickSettings, Bool>)] {
        [
            ("swipeToSnap", \.swipeToSnap),
            ("pinchToFillRestore", \.pinchToFillRestore),
            ("livePreview", \.livePreview),
        ]
    }
}
