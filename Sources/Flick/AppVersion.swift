import Foundation

/// The version `task bundle` stamped into Info.plist.
enum AppVersion {
    static let short = info("CFBundleShortVersionString")
    static let build = info("CFBundleVersion")

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}
