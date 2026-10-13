import AppKit
import UserNotifications

/// Posts NotificationPolicy notifications and routes clicks back to the session.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let navigation: Navigation
    private let lookup: (String) -> Session?

    init(navigation: Navigation, lookup: @escaping (String) -> Session?) {
        self.navigation = navigation
        self.lookup = lookup
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
            if let sessionID { self.open(sessionID) }
            completionHandler()
        }
    }

    /// A notification means "go answer it": jump to the terminal, or show the session in the app.
    private func open(_ sessionID: String) {
        guard let session = lookup(sessionID), TerminalNavigator.canFocus(session) else {
            navigation.open(sessionID: sessionID)
            return
        }
        // Clicking a notification activates this app, and that activation can land after the
        // click callback; handing focus to the terminal before it would be undone. Wait for it.
        afterActivation { [weak self] in
            guard let self else { return }
            if case .failed = TerminalNavigator.focus(session) {
                self.navigation.open(sessionID: sessionID)
            }
        }
    }

    static let activationTimeout: TimeInterval = 1

    /// Runs `action` once this app is active (or after a short timeout if it never becomes active).
    private func afterActivation(_ action: @escaping @MainActor () -> Void) {
        if NSApp.isActive {
            action()
            return
        }
        var observer: NSObjectProtocol?
        var done = false
        let run = {
            guard !done else { return }
            done = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            action()
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { run() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationTimeout) { run() }
    }
}
