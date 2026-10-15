import FlickCore
import Sparkle

/// Sparkle's updater: checks the appcast on GitHub and installs updates the user accepts.
/// An update found by a scheduled check waits in the menu (Sparkle's gentle reminders) instead
/// of opening a window over whatever the user is doing.
@MainActor
final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    /// The version a scheduled check found, until the user looks at it or the session ends.
    private(set) var availableVersion: String?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// False while a check or an update is in progress.
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Sparkle keeps this in its own defaults keys.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Seconds between scheduled checks; Sparkle keeps it in its own defaults key too.
    var updateCheckInterval: TimeInterval {
        get { controller?.updater.updateCheckInterval ?? UpdateCheckInterval.day.seconds }
        set { controller?.updater.updateCheckInterval = newValue }
    }

    /// Checks now and shows Sparkle's window: up to date, an error, or the update to install.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate (called on the main thread)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
