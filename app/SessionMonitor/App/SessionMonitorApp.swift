import SwiftUI

@main
struct SessionMonitorApp: App {
    @State private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: monitor.store)
        } label: {
            MenuBarLabel(store: monitor.store)
        }
    }
}

/// Owns the store and keeps it fresh: FSEvents for file changes, a timer for process liveness.
@MainActor
final class Monitor {
    static let livenessInterval: TimeInterval = 5

    let store: SessionStore
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

// Temporary M2 views to see the core working; replaced by the real UI in M3 (#11).

private struct MenuBarLabel: View {
    let store: SessionStore

    var body: some View {
        let all = Array(store.sessions.values)
        let needs = all.filter(\.state.needsResponse).count
        let working = all.filter { $0.state == .working }.count
        Text(needs > 0 ? "SM ●\(needs)" : working > 0 ? "SM ◐\(working)" : "SM")
    }
}

private struct MenuContent: View {
    let store: SessionStore

    var body: some View {
        let sessions = store.sessions.values.sorted { $0.updatedAt > $1.updatedAt }
        if sessions.isEmpty {
            Text("등록된 세션 없음")
        }
        ForEach(sessions) { session in
            Text("\(session.group ?? "미분류") · \(label(session.state)) · \(session.lastPrompt?.prefix(30) ?? session.id.prefix(8))")
        }
        if !store.unregistered.isEmpty {
            Divider()
            Text("미등록 \(store.unregistered.count)개")
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func label(_ state: SessionState) -> String {
        switch state {
        case .working: return "생성중"
        case .idle: return "응답 완료"
        case .needsResponse: return "응답 필요"
        case .ended: return "종료"
        }
    }
}
