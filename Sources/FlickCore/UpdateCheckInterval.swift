import Foundation

/// How often Flick checks GitHub for an update: the choices of the settings window's picker.
public enum UpdateCheckInterval: Int, CaseIterable, Equatable, Sendable {
    case hour = 3600
    case fourHours = 14400
    case eightHours = 28800
    case day = 86400

    public var seconds: TimeInterval { TimeInterval(rawValue) }

    /// The choice nearest to an interval Sparkle has stored, which may be any number of seconds.
    public init(closestTo seconds: TimeInterval) {
        self = Self.allCases.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) }!
    }
}
