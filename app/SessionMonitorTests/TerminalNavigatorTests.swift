import XCTest
@testable import SessionMonitor

@MainActor
final class TerminalNavigatorTests: XCTestCase {
    func testWindowTitleIgnoresClaudeStatusGlyph() {
        XCTAssertTrue(TerminalNavigator.windowTitle("◐ session-monitor", matches: "session-monitor"))
        XCTAssertTrue(TerminalNavigator.windowTitle("✳ 결제 리팩토링", matches: "결제 리팩토링"))
        XCTAssertTrue(TerminalNavigator.windowTitle("session-monitor", matches: "session-monitor"))
        XCTAssertFalse(TerminalNavigator.windowTitle("◐ session-monitor-2", matches: "session-monitor"))
        XCTAssertFalse(TerminalNavigator.windowTitle("◐ ", matches: ""))
    }

    func testParentPID() {
        XCTAssertEqual(TerminalNavigator.parentPID(of: getpid()), getppid())
        XCTAssertNil(TerminalNavigator.parentPID(of: 99_999_999))
    }

    func testEndedOrProcessLessSessionsCannotBeFocused() {
        var session = Session(id: Fixture.sessionA, isRegistered: true, date: Fixture.base)
        XCTAssertFalse(TerminalNavigator.canFocus(session), "no process yet")
        session.process = SessionProcess(pid: 4242, tty: "ttys003", terminal: TerminalInfo(program: "WarpTerminal"), since: Fixture.base)
        XCTAssertTrue(TerminalNavigator.canFocus(session))
        session.state = .ended(.processGone)
        XCTAssertFalse(TerminalNavigator.canFocus(session))
        XCTAssertEqual(TerminalNavigator.focus(session), .failed("세션이 종료되었습니다"))
    }

    func testUnknownProgramHasNoFallbackApp() {
        XCTAssertNil(TerminalNavigator.terminalApp(program: "SomethingElse"))
    }
}
