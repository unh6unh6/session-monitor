import Foundation
@testable import SessionMonitor

enum Fixture {
    static let sessionA = "aaaaaaaa-0000-4000-8000-000000000001"
    static let sessionB = "bbbbbbbb-0000-4000-8000-000000000002"
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// A HookEvent as hook.sh would produce it, `offset` seconds after `base`.
    static func event(_ name: String, id: String = sessionA, at offset: TimeInterval = 0,
                      pid: Int32 = 4242, tty: String? = nil, _ fields: [String: String] = [:]) -> HookEvent {
        HookEvent(sessionID: id, name: name, timestamp: base.addingTimeInterval(offset), pid: pid, tty: tty,
                  terminal: TerminalInfo(program: "WarpTerminal"), fields: fields)
    }

    /// Raw record JSON in the hook.sh spool format.
    static func record(_ name: String, _ id: String = sessionA, pid: Int32 = 4242, extra: [String: Any] = [:]) -> Data {
        var input: [String: Any] = ["session_id": id, "hook_event_name": name, "cwd": "/tmp/proj"]
        input.merge(extra) { _, new in new }
        let root: [String: Any] = [
            "schema": 1, "ts": "2026-10-13T22:54:50+0900", "pid": pid, "tty": "ttys003",
            "term": ["program": "WarpTerminal", "session": "", "iterm": "", "tmux": "", "tmux_pane": ""],
            "input": input,
        ]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sm-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Repo root, located from this source file (app/SessionMonitorTests/TestSupport.swift).
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

final class FakeProbe: ProcessProbing {
    var alive: Set<Int32> = [4242]
    func isAlive(pid: Int32, startedBefore: Date) -> Bool { alive.contains(pid) }
}
