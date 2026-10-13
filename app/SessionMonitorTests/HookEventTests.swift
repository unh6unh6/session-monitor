import XCTest
@testable import SessionMonitor

final class HookEventTests: XCTestCase {
    func testParsesHookRecord() throws {
        let data = Fixture.record("Stop", extra: ["last_assistant_message": "done", "new_field": ["nested": 1]])
        let event = try XCTUnwrap(HookEvent.parse(data))
        XCTAssertEqual(event.sessionID, Fixture.sessionA)
        XCTAssertEqual(event.kind, .stop)
        XCTAssertEqual(event["last_assistant_message"], "done")
        XCTAssertEqual(event["cwd"], "/tmp/proj")
        XCTAssertEqual(event.pid, 4242)
        XCTAssertEqual(event.tty, "ttys003")
        XCTAssertEqual(event.terminal.program, "WarpTerminal")
        XCTAssertEqual(event.timestamp, HookEvent.parseTimestamp("2026-10-13T13:54:50+0000"))
    }

    func testUnknownEventNameStillParses() throws {
        let event = try XCTUnwrap(HookEvent.parse(Fixture.record("SomethingNew")))
        XCTAssertNil(event.kind)
    }

    func testRejectsMalformedRecords() {
        XCTAssertNil(HookEvent.parse(Data("not json".utf8)))
        XCTAssertNil(HookEvent.parse(Data(#"{"input":{"hook_event_name":"Stop"}}"#.utf8)))
    }

    func testUnknownTtyBecomesNil() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixture.record("SessionStart")) as? [String: Any])
        root["tty"] = "??"
        let event = try XCTUnwrap(HookEvent.parse(JSONSerialization.data(withJSONObject: root)))
        XCTAssertNil(event.tty)
    }

    func testMissingTimestampUsesFallback() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixture.record("Stop")) as? [String: Any])
        root["ts"] = nil
        let event = try XCTUnwrap(HookEvent.parse(JSONSerialization.data(withJSONObject: root), fallbackDate: Fixture.base))
        XCTAssertEqual(event.timestamp, Fixture.base)
    }
}
