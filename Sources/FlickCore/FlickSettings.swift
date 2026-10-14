import Foundation

/// What the user turned on or off in the settings window. Launch at login isn't part of it:
/// macOS owns that state.
public struct FlickSettings: Equatable, Sendable {
    public var swipeToSnap = true
    public var pinchToFillRestore = true
    public var scrollWhileDragging = true
    public var livePreview = true

    public init() {}

    /// Reads the settings from `defaults`. Keys that were never written keep their default.
    public init(defaults: UserDefaults) {
        for (key, path) in Self.keys {
            if let value = defaults.object(forKey: key) as? Bool {
                self[keyPath: path] = value
            }
        }
    }

    public func save(to defaults: UserDefaults) {
        for (key, path) in Self.keys {
            defaults.set(self[keyPath: path], forKey: key)
        }
    }

    private static var keys: [(String, WritableKeyPath<FlickSettings, Bool>)] {
        [
            ("swipeToSnap", \.swipeToSnap),
            ("pinchToFillRestore", \.pinchToFillRestore),
            ("scrollWhileDragging", \.scrollWhileDragging),
            ("livePreview", \.livePreview),
        ]
    }
}
