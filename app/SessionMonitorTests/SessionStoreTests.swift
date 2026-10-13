import XCTest
@testable import SessionMonitor

@MainActor
final class SessionStoreTests: XCTestCase {
    private var root: URL!
    private var files: MonitorFiles!
    private var stateURL: URL!
    private var probe: FakeProbe!
    private let fm = FileManager.default

    override func setUp() async throws {
        root = Fixture.tempDir()
        files = MonitorFiles(root: root)
        stateURL = root.appendingPathComponent("state/sessions.json")
        probe = FakeProbe()
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: root)
    }

    private func makeStore() -> SessionStore {
        SessionStore(files: files, stateURL: stateURL, probe: probe, now: { Fixture.base.addingTimeInterval(1000) })
    }

    private func spool(_ name: String, _ id: String = Fixture.sessionA, file: String, pid: Int32 = 4242,
                       extra: [String: Any] = [:], mtime: TimeInterval) throws {
        let dir = root.appendingPathComponent("spool/\(id)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file)
        try Fixture.record(name, id, pid: pid, extra: extra).write(to: url)
        try fm.setAttributes([.modificationDate: Fixture.base.addingTimeInterval(mtime)], ofItemAtPath: url.path)
    }

    private func makeRegistered(_ id: String = Fixture.sessionA, group: String? = "이슈A") throws {
        try fm.createDirectory(at: root.appendingPathComponent("sessions/\(id)"), withIntermediateDirectories: true)
        if let group { try Data((group + "\n").utf8).write(to: root.appendingPathComponent("sessions/\(id)/group")) }
    }

    func testIngestsSpoolInMtimeOrderAndDeletesFiles() throws {
        try makeRegistered()
        // Names sort the other way round; mtime must win.
        try spool("Stop", file: "1-a.json", extra: ["last_assistant_message": "answer"], mtime: 2)
        try spool("UserPromptSubmit", file: "2-b.json", extra: ["prompt": "question"], mtime: 1)
        let store = makeStore()
        store.refresh()

        let session = try XCTUnwrap(store.sessions[Fixture.sessionA])
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.group, "이슈A")
        XCTAssertEqual(session.lastPrompt, "question")
        XCTAssertEqual(session.lastResponse, "answer")
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("spool/\(Fixture.sessionA)").path).isEmpty)
    }

    func testIgnoresInFlightTempFilesAndDropsCorruptOnes() throws {
        try makeRegistered()
        let dir = root.appendingPathComponent("spool/\(Fixture.sessionA)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: dir.appendingPathComponent("3-x.json.tmp.99"))
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("4-y.json"))
        let store = makeStore()
        store.refresh()

        let left = try fm.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left, ["3-x.json.tmp.99"])
    }

    func testPersistsAcrossRestart() throws {
        try makeRegistered()
        try spool("UserPromptSubmit", file: "1.json", extra: ["prompt": "keep me"], mtime: 1)
        makeStore().refresh()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.sessions[Fixture.sessionA]?.lastPrompt, "keep me")
    }

    func testRegistrationWithoutEventsShowsUp() throws {
        try makeRegistered(group: nil)
        let store = makeStore()
        store.refresh()
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.state, .idle)
        XCTAssertNil(store.sessions[Fixture.sessionA]?.group)
    }

    func testLeaveRemovesSession() throws {
        try makeRegistered()
        try spool("Stop", file: "1.json", mtime: 1)
        let store = makeStore()
        store.refresh()
        XCTAssertNotNil(store.sessions[Fixture.sessionA])

        try fm.removeItem(at: root.appendingPathComponent("sessions/\(Fixture.sessionA)"))
        store.refresh()
        XCTAssertNil(store.sessions[Fixture.sessionA])
    }

    func testDeadProcessEndsSession() throws {
        try makeRegistered()
        try spool("UserPromptSubmit", file: "1.json", mtime: 1)
        let store = makeStore()
        var transitions: [(SessionState, SessionState)] = []
        store.onTransition = { session, before in transitions.append((before, session.state)) }
        store.refresh()
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.state, .working)

        probe.alive = []
        store.refresh()
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.state, .ended(.processGone))
        XCTAssertEqual(transitions.map(\.1), [.working, .ended(.processGone)])
    }

    func testResumeInNewProcessRevivesEndedSession() throws {
        try makeRegistered()
        try spool("UserPromptSubmit", file: "1.json", extra: ["prompt": "first"], mtime: 1)
        try spool("SessionEnd", file: "2.json", extra: ["reason": "prompt_input_exit"], mtime: 2)
        let store = makeStore()
        store.refresh()
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.state, .ended(.exit(reason: "prompt_input_exit")))

        // `claude --resume` starts a new process with the same session id.
        probe.alive = [5000]
        try spool("SessionStart", file: "3.json", pid: 5000, extra: ["source": "resume"], mtime: 3)
        store.refresh()
        let session = try XCTUnwrap(store.sessions[Fixture.sessionA])
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.process?.pid, 5000)
        XCTAssertEqual(session.group, "이슈A")
        XCTAssertEqual(session.lastPrompt, "first", "history carries over")
    }

    func testSeenSessionsAreUnregisteredAndRegisterMovesThem() throws {
        try fm.createDirectory(at: files.seenDir, withIntermediateDirectories: true)
        try Fixture.record("UserPromptSubmit", Fixture.sessionB, extra: ["prompt": "hi"])
            .write(to: files.seenDir.appendingPathComponent("\(Fixture.sessionB).json"))
        let store = makeStore()
        store.refresh()
        XCTAssertEqual(store.unregistered[Fixture.sessionB]?.state, .working)
        XCTAssertTrue(store.sessions.isEmpty)

        try store.register(Fixture.sessionB, group: " 이슈B ")
        XCTAssertNil(store.unregistered[Fixture.sessionB])
        XCTAssertEqual(store.sessions[Fixture.sessionB]?.group, "이슈B")
        XCTAssertEqual(store.sessions[Fixture.sessionB]?.lastPrompt, "hi", "seen event seeds the timeline")

        try store.setGroup(Fixture.sessionB, group: nil)
        XCTAssertNil(store.sessions[Fixture.sessionB]?.group)
        XCTAssertThrowsError(try store.setGroup(Fixture.sessionB, group: "a/b"))

        try store.unregister(Fixture.sessionB)
        XCTAssertNil(store.sessions[Fixture.sessionB])
    }

    func testOldEndedSeenFilesAreCleanedUp() throws {
        try fm.createDirectory(at: files.seenDir, withIntermediateDirectories: true)
        let url = files.seenDir.appendingPathComponent("\(Fixture.sessionB).json")
        try Fixture.record("SessionEnd", Fixture.sessionB, extra: ["reason": "other"]).write(to: url)
        try fm.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: url.path)
        let store = SessionStore(files: files, stateURL: stateURL, probe: probe)
        store.refresh()
        XCTAssertNil(store.unregistered[Fixture.sessionB])
        XCTAssertFalse(fm.fileExists(atPath: url.path))
    }

    func testRejectsInvalidIDs() {
        let store = makeStore()
        XCTAssertThrowsError(try store.register("../etc", group: nil))
    }

    /// End to end with the real plugin hook: hook.sh writes, the store reads.
    func testWithRealHookScript() throws {
        let hook = Fixture.repoRoot.appendingPathComponent("plugin/scripts/hook.sh")
        let cli = Fixture.repoRoot.appendingPathComponent("plugin/scripts/session-monitor.sh")
        try XCTSkipUnless(fm.isExecutableFile(atPath: hook.path), "plugin not found at \(hook.path)")

        func run(_ executable: URL, _ args: [String] = [], stdin: String = "") throws {
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            process.environment = ["SESSION_MONITOR_HOME": root.path, "CLAUDE_PID": "4242", "PATH": "/usr/bin:/bin",
                                   "HOME": root.path, "TERM_PROGRAM": "WarpTerminal"]
            let pipe = Pipe()
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            pipe.fileHandleForWriting.write(Data(stdin.utf8))
            try pipe.fileHandleForWriting.close()
            process.waitUntilExit()
        }
        func hookEvent(_ name: String, _ extra: String = "") throws {
            try run(hook, stdin: #"{"session_id":"\#(Fixture.sessionA)","hook_event_name":"\#(name)","cwd":"/tmp/p"\#(extra)}"#)
        }

        try hookEvent("SessionStart", #","source":"startup""#)
        try hookEvent("UserPromptSubmit", #","prompt":"before register""#)
        let store = makeStore()
        store.refresh()
        XCTAssertEqual(store.unregistered[Fixture.sessionA]?.state, .working)

        try run(cli, ["register", Fixture.sessionA, "이슈A"])
        try hookEvent("PermissionRequest", #","tool_name":"Bash""#)
        store.refresh()
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.state, .needsResponse(.permission(tool: "Bash")))
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.lastPrompt, "before register")
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.group, "이슈A")
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.process?.terminal.program, "WarpTerminal")

        try hookEvent("PostToolUse", #","tool_name":"Bash""#)
        try hookEvent("Stop", #","last_assistant_message":"all done""#)
        store.refresh()
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.state, .idle)
        XCTAssertEqual(store.sessions[Fixture.sessionA]?.lastResponse, "all done")
    }
}
