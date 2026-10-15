import FlickCore
import Sparkle

/// Sparkle's updater: checks the appcast on GitHub and installs updates the user accepts.
/// An update found by a scheduled check waits in the menu (Sparkle's gentle reminders) instead
/// of opening a window over whatever the user is doing; a dot on the menu-bar icon and one
/// notification per version point at it until the user installs or skips it.
@MainActor
final class Updater: NSObject, @preconcurrency SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate
{
    private var controller: SPUStandardUpdaterController?
    private let notifier = UpdateNotifier()
    private let notificationPolicy = UpdateNotificationPolicy()
    private var pending = PendingUpdate()

    /// The version waiting for the user: found by a scheduled check or postponed with *Remind Me
    /// Later*, until they install or skip it.
    @Published private(set) var availableVersion: String?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        notifier.onClick = { [weak self] in self?.checkForUpdates() }
        // An update was still waiting when Flick quit: look again now rather than at the next
        // scheduled check, which can be up to a day away.
        if pending.takeWaitingFromLastLaunch() {
            controller?.updater.checkForUpdatesInBackground()
        }
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

    // MARK: - SPUUpdaterDelegate (called on the main thread)

    func updater(
        _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .install: pending.userChose(.install, version: updateItem.displayVersionString)
        case .skip: pending.userChose(.skip, version: updateItem.displayVersionString)
        case .dismiss: pending.userChose(.later, version: updateItem.displayVersionString)
        @unknown default: return
        }
        availableVersion = pending.version
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
            pending.found(update.displayVersionString)
            availableVersion = pending.version
            if notificationPolicy.shouldNotify(about: update.versionString) {
                notifier.post(version: update.displayVersionString)
            }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        notifier.removeDelivered()
    }
}
