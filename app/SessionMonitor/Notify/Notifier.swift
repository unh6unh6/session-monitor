import AppKit
import UserNotifications

/// Posts NotificationPolicy notifications and routes clicks back to the session.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let navigation: Navigation

    init(navigation: Navigation) {
        self.navigation = navigation
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("SessionMonitor: notification authorization failed: \(error)") }
            else if !granted { NSLog("SessionMonitor: notifications not allowed") }
        }
    }

    func sessionChanged(_ session: Session, from before: SessionState) {
        guard let content = NotificationPolicy.content(
            for: session, from: before, now: Date(), settings: .load()) else {
            // Answered elsewhere (e.g. in the terminal): the "응답 필요" banner is stale.
            if before.needsResponse { clear(session.id) }
            return
        }
        // The user is already looking at this session.
        if NSApp.isActive, navigation.isShowing(session.id) { return }

        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.subtitle = content.subtitle
        notification.body = content.body
        notification.sound = content.kind == .needsResponse ? .default : nil
        notification.userInfo = ["sessionID": content.sessionID]
        notification.threadIdentifier = session.group ?? "ungrouped"
        // One notification per session: a newer one replaces the older.
        center.add(UNNotificationRequest(identifier: "session-\(session.id)", content: notification, trigger: nil))
    }

    /// Clears a session's notification once it no longer applies (e.g. the user answered).
    func clear(_ sessionID: String) {
        center.removeDeliveredNotifications(withIdentifiers: ["session-\(sessionID)"])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        Task { @MainActor in
            if let sessionID { self.navigation.open(sessionID: sessionID) }
            completionHandler()
        }
    }
}
