import SwiftUI

@main
struct SessionMonitorApp: App {
    @State private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: monitor.store, navigation: monitor.navigation)
        } label: {
            MenuBarLabel(summary: StatusSummary(monitor.store.sessions.values))
        }
        .menuBarExtraStyle(.window)

        Window("Session Monitor", id: MainWindow.id) {
            MainWindow(store: monitor.store, navigation: monitor.navigation)
        }
        .defaultSize(width: 1000, height: 640)
    }
}

/// Selection shared by the menu bar and the main window.
@MainActor
@Observable
final class Navigation {
    var sidebar: SidebarItem? = .all
    var sessionID: String?
    /// Session waiting for a new group name (asked by the main window).
    var newGroupSessionID: String?

    /// Shows a session in the main window, switching the sidebar if it isn't listed there.
    func show(_ session: Session) {
        sessionID = session.id
        if !session.isRegistered {
            sidebar = .unregistered
        } else if sidebar == .unregistered || (sidebar != .all && sidebar != (session.group.map(SidebarItem.group) ?? .ungrouped)) {
            sidebar = .all
        }
    }
}

/// Owns the store and keeps it fresh: FSEvents for file changes, a timer for process liveness.
@MainActor
final class Monitor {
    static let livenessInterval: TimeInterval = 5

    let store: SessionStore
    let navigation = Navigation()
    private var watcher: DirectoryWatcher?
    private var timer: Timer?

    init() {
        // Unit tests run inside this app as the test host; keep it off the user's real data.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("SessionMonitorTestHost")
            store = SessionStore(files: MonitorFiles(root: scratch), stateURL: scratch.appendingPathComponent("sessions.json"))
            return
        }
        let files = MonitorFiles(root: MonitorFiles.defaultRoot)
        try? FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
        store = SessionStore(files: files, stateURL: SessionStore.defaultStateURL)
        store.refresh()
        watcher = DirectoryWatcher(url: files.root) { [weak self] in
            MainActor.assumeIsolated { self?.store.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.livenessInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refresh() }
        }
    }
}
