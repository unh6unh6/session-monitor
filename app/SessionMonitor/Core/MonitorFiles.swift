import Foundation

/// Reads and writes ~/.session-monitor, the directory shared with the Claude Code plugin.
/// Layout and write rules: DECISIONS.md D9. Every write is temp file + rename.
struct MonitorFiles {
    let root: URL
    private let fileManager = FileManager.default

    static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["SESSION_MONITOR_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-monitor", isDirectory: true)
    }

    var sessionsDir: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    var spoolDir: URL { root.appendingPathComponent("spool", isDirectory: true) }
    var seenDir: URL { root.appendingPathComponent("seen", isDirectory: true) }

    // MARK: Registry (sessions/<id>/)

    struct Registration: Equatable {
        var group: String?
        var recap: String?
        var previousSessionID: String?
        var registeredAt: Date?
    }

    func registrations() -> [String: Registration] {
        var result: [String: Registration] = [:]
        for id in subdirectoryNames(of: sessionsDir) where Self.isValidID(id) {
            let dir = sessionsDir.appendingPathComponent(id, isDirectory: true)
            var registration = Registration()
            registration.group = readTrimmed(dir.appendingPathComponent("group"))
            registration.recap = readTrimmed(dir.appendingPathComponent("recap.md"))
            if let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
               let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                registration.previousSessionID = (meta["previous"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                registration.registeredAt = (meta["registered_at"] as? String).flatMap(HookEvent.parseTimestamp)
            }
            result[id] = registration
        }
        return result
    }

    func register(_ id: String, group: String?) throws {
        guard Self.isValidID(id) else { throw MonitorFilesError.invalidID(id) }
        let dir = sessionsDir.appendingPathComponent(id, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let meta: [String: Any] = [
                "schema": 1, "session_id": id, "registered_at": Self.timestamp(Date()),
                "previous": "", "via": "app",
            ]
            try atomicWrite(try JSONSerialization.data(withJSONObject: meta), to: dir.appendingPathComponent("meta.json"))
            // Same seeding as session-monitor.sh register: the seen event starts the timeline.
            let seen = seenDir.appendingPathComponent("\(id).json")
            if fileManager.fileExists(atPath: seen.path) {
                let spool = spoolDir.appendingPathComponent(id, isDirectory: true)
                try fileManager.createDirectory(at: spool, withIntermediateDirectories: true)
                let target = spool.appendingPathComponent("0-seen.json")
                try? fileManager.removeItem(at: target)
                try fileManager.moveItem(at: seen, to: target)
            }
        }
        try setGroup(id, group: group)
    }

    func setGroup(_ id: String, group: String?) throws {
        guard Self.isValidID(id) else { throw MonitorFilesError.invalidID(id) }
        let file = sessionsDir.appendingPathComponent(id, isDirectory: true).appendingPathComponent("group")
        let name = group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            try? fileManager.removeItem(at: file)
            return
        }
        guard !name.contains("/"), !name.contains("\n") else { throw MonitorFilesError.invalidGroup(name) }
        try atomicWrite(Data((name + "\n").utf8), to: file)
    }

    /// Registration goes first so hooks stop spooling before the spool is removed.
    func unregister(_ id: String) throws {
        guard Self.isValidID(id) else { throw MonitorFilesError.invalidID(id) }
        try? fileManager.removeItem(at: sessionsDir.appendingPathComponent(id, isDirectory: true))
        try? fileManager.removeItem(at: spoolDir.appendingPathComponent(id, isDirectory: true))
    }

    // MARK: Spool (spool/<id>/*.json)

    struct SpoolEntry {
        let url: URL
        let event: HookEvent?
    }

    /// Pending events per session, oldest first. Order: file mtime (ns on APFS), then name.
    /// `event` is nil for unreadable files, which should still be removed.
    func pendingSpool() -> [String: [SpoolEntry]] {
        var result: [String: [SpoolEntry]] = [:]
        for id in subdirectoryNames(of: spoolDir) where Self.isValidID(id) {
            let dir = spoolDir.appendingPathComponent(id, isDirectory: true)
            let files = jsonFiles(in: dir)
            guard !files.isEmpty else { continue }
            result[id] = files.map { file in
                SpoolEntry(url: file.url, event: (try? Data(contentsOf: file.url)).flatMap {
                    HookEvent.parse($0, fallbackDate: file.modified)
                })
            }
        }
        return result
    }

    func removeSpoolFiles(_ urls: [URL]) {
        for url in urls { try? fileManager.removeItem(at: url) }
    }

    // MARK: Seen (seen/<id>.json)

    struct SeenEntry {
        let event: HookEvent
        let modified: Date
        let url: URL
    }

    func seenEvents() -> [SeenEntry] {
        jsonFiles(in: seenDir).compactMap { file in
            guard let data = try? Data(contentsOf: file.url),
                  let event = HookEvent.parse(data, fallbackDate: file.modified) else { return nil }
            return SeenEntry(event: event, modified: file.modified, url: file.url)
        }
    }

    func removeSeen(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    // MARK: Helpers

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.string(from: date)
    }

    private func subdirectoryNames(of dir: URL) -> [String] {
        let items = (try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }

    private func jsonFiles(in dir: URL) -> [(url: URL, modified: Date)] {
        let items = (try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { $0.pathExtension == "json" }  // skips in-flight "*.json.tmp.<pid>" files
            .map { url in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            .sorted { $0.modified == $1.modified ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.modified < $1.modified }
    }

    private func readTrimmed(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

enum MonitorFilesError: Error, Equatable {
    case invalidID(String)
    case invalidGroup(String)
}
