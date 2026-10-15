import Sparkle

/// Sparkle's updater: checks the appcast on GitHub and installs updates the user accepts.
@MainActor
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// False while a check or an update is in progress.
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Sparkle keeps this in its own defaults keys.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Checks now and shows Sparkle's window: up to date, an error, or the update to install.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
