import UserNotifications

/// Posts "Flick X is available" when a scheduled check finds an update; clicking it runs
/// `onClick`. macOS asks for permission with the first notification, not at launch; declined,
/// the menu-bar dot is all the user gets.
@MainActor
final class UpdateNotifier: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private static let identifier = "update-available"
    private let center = UNUserNotificationCenter.current()
    var onClick: () -> Void = {}

    override init() {
        super.init()
        center.delegate = self
    }

    func post(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Flick \(version) is available"
        content.body = "Click to see what's new and install."
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        let center = self.center
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }

    /// Takes the notification out of Notification Center once the user has seen the update.
    func removeDelivered() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    // MARK: - UNUserNotificationCenterDelegate (called on the main thread)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        onClick()
        completionHandler()
    }

    /// Shows the banner also while Flick is the active app, e.g. with the settings window open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
