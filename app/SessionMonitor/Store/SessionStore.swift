import Foundation
import Observation

/// App-side source of truth for sessions.
///
/// Registered sessions are rebuilt from spool events and persisted to Application Support
/// (spool files are deleted once persisted). Unregistered sessions come from seen/ and are
/// kept in memory only. Design: docs/DECISIONS.md D9, D10.
@MainActor
@Observable
final class SessionStore {
    /// Registered sessions, persisted.
    private(set) var sessions: [String: Session] = [:]
    /// Unregistered sessions seen by the hook, shown dimmed.
    private(set) var unregistered: [String: Session] = [:]
    /// The plugin hook has run at least once (it creates pids/ on SessionStart).
    private(set) var pluginDetected = false

    /// Called for registered sessions whose state changed: (session after, state before).
    @ObservationIgnored var onTransition: ((Session, SessionState) -> Void)?

    /// Seen files of ended unregistered sessions are deleted after this long.
    static let seenRetention: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private let files: MonitorFiles
    @ObservationIgnored private let stateURL: URL
    @ObservationIgnored private let probe: ProcessProbing
    @ObservationIgnored private let now: () -> Date

    init(files: MonitorFiles, stateURL: URL, probe: ProcessProbing = ProcessProbe(), now: @escaping () -> Date = Date.init) {
        self.files = files
        self.stateURL = stateURL
        self.probe = probe
        self.now = now
        load()
    }

    static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionMonitor", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    var groups: [String] {
        Set(sessions.values.compactMap(\.group)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Refresh

    /// Ingests spool, syncs registrations and seen files, then checks process liveness.
    func refresh() {
        var changed = ingestSpool()
        changed = syncRegistrations() || changed
        changed = checkLiveness() || changed
        loadSeen()
        let detected = FileManager.default.fileExists(atPath: files.root.appendingPathComponent("pids").path)
        if detected != pluginDetected { pluginDetected = detected }
        if changed { save() }
    }

    private func ingestSpool() -> Bool {
        let pending = files.pendingSpool()
        guard !pending.isEmpty else { return false }
        var processed: [URL] = []
        for (id, entries) in pending {
            var session = sessions[id] ?? Session(id: id, isRegistered: true,
                                                  date: entries.first?.event?.timestamp ?? now())
            let before = session.state
            for entry in entries {
                if let event = entry.event { SessionReducer.apply(event, to: &session) }
                processed.append(entry.url)
            }
            sessions[id] = session
            notifyIfChanged(session, from: before)
        }
        // Persist before deleting so a crash can only re-apply, never lose, events.
        save()
        files.removeSpoolFiles(processed)
        return true
    }

    private func syncRegistrations() -> Bool {
        let registrations = files.registrations()
        var changed = false
        for id in sessions.keys where registrations[id] == nil {
            sessions[id] = nil  // left via /session-monitor:leave or the app
            changed = true
        }
        for (id, registration) in registrations {
            var session = sessions[id] ?? Session(id: id, isRegistered: true, date: registration.registeredAt ?? now())
            let before = session
            session.isRegistered = true
            session.group = registration.group
            session.recap = registration.recap
            session.previousSessionID = registration.previousSessionID
            if session != before || sessions[id] == nil {
                sessions[id] = session
                changed = true
            }
        }
        return changed
    }

    private func loadSeen() {
        var result: [String: Session] = [:]
        for entry in files.seenEvents() where sessions[entry.event.sessionID] == nil {
            var session = Session(id: entry.event.sessionID, isRegistered: false, date: entry.event.timestamp)
            SessionReducer.apply(entry.event, to: &session)
            markIfGone(&session)
            if session.state.isEnded, now().timeIntervalSince(entry.modified) > Self.seenRetention {
                files.removeSeen(entry.url)
                continue
            }
            result[session.id] = session
        }
        if result != unregistered { unregistered = result }
    }

    @discardableResult
    func checkLiveness() -> Bool {
        var changed = false
        for (id, var session) in sessions {
            let before = session.state
            markIfGone(&session)
            if session.state != before {
                sessions[id] = session
                notifyIfChanged(session, from: before)
                changed = true
            }
        }
        return changed
    }

    private func markIfGone(_ session: inout Session) {
        guard !session.state.isEnded, let process = session.process,
              !probe.isAlive(pid: process.pid, startedBefore: process.since) else { return }
        SessionReducer.markProcessGone(&session, at: now())
    }

    private func notifyIfChanged(_ session: Session, from before: SessionState) {
        if session.state != before { onTransition?(session, before) }
    }

    // MARK: Actions (write the shared files; the next refresh picks them up)

    func register(_ id: String, group: String?) throws {
        try files.register(id, group: group)
        refresh()
    }

    func setGroup(_ id: String, group: String?) throws {
        try files.setGroup(id, group: group)
        refresh()
    }

    func unregister(_ id: String) throws {
        try files.unregister(id)
        refresh()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let list = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessions = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sessions.values.sorted { $0.id < $1.id })
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("SessionMonitor: failed to save state: \(error)")
        }
    }
}
