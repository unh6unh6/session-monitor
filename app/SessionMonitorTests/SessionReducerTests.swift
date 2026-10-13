import XCTest
@testable import SessionMonitor

final class SessionReducerTests: XCTestCase {
    private func run(_ events: [HookEvent]) -> Session {
        var session = Session(id: Fixture.sessionA, isRegistered: true, date: Fixture.base)
        for event in events { SessionReducer.apply(event, to: &session) }
        return session
    }

    func testPromptThenStopGoesWorkingThenIdle() {
        var session = run([Fixture.event("SessionStart", ["source": "startup"]),
                           Fixture.event("UserPromptSubmit", at: 1, ["prompt": "hello"])])
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.lastPrompt, "hello")
        XCTAssertEqual(session.firstPrompt, "hello")

        SessionReducer.apply(Fixture.event("Stop", at: 5, ["last_assistant_message": "hi there"]), to: &session)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastResponse, "hi there")
        XCTAssertEqual(session.stateChangedAt, Fixture.base.addingTimeInterval(5))
        XCTAssertEqual(session.timeline.map(\.kind), [.started, .prompt, .response])
    }

    func testPermissionRequestThenApprovalReturnsToWorking() {
        var session = run([Fixture.event("UserPromptSubmit", ["prompt": "x"]),
                           Fixture.event("PermissionRequest", at: 1, ["tool_name": "Bash"])])
        XCTAssertEqual(session.state, .needsResponse(.permission(tool: "Bash")))

        SessionReducer.apply(Fixture.event("Notification", at: 7, ["notification_type": "permission_prompt"]), to: &session)
        XCTAssertEqual(session.state, .needsResponse(.permission(tool: "Bash")), "trailing notification keeps the precise reason")

        SessionReducer.apply(Fixture.event("PostToolUse", at: 9, ["tool_name": "Bash"]), to: &session)
        XCTAssertEqual(session.state, .working)
    }

    func testAskUserQuestionIsAQuestion() {
        let session = run([Fixture.event("UserPromptSubmit"),
                           Fixture.event("PermissionRequest", at: 1, ["tool_name": "AskUserQuestion"])])
        XCTAssertEqual(session.state, .needsResponse(.question))
    }

    func testNotificationAloneNeedsResponseOnlyWhileWorking() {
        var session = run([Fixture.event("UserPromptSubmit"),
                           Fixture.event("Notification", at: 1, ["notification_type": "permission_prompt", "message": "m"])])
        XCTAssertEqual(session.state, .needsResponse(.other(message: "m")))

        session = run([Fixture.event("Stop"), Fixture.event("Notification", at: 60, ["notification_type": "idle_prompt"])])
        XCTAssertEqual(session.state, .idle)
    }

    func testLatePostToolUseAfterStopIsIgnored() {
        let session = run([Fixture.event("UserPromptSubmit"),
                           Fixture.event("PermissionRequest", at: 1, ["tool_name": "Bash"]),
                           Fixture.event("Stop", at: 3),
                           Fixture.event("PostToolUse", at: 3)])
        XCTAssertEqual(session.state, .idle)
    }

    func testStopFailureRecordsErrorUntilNextPrompt() {
        var session = run([Fixture.event("UserPromptSubmit"), Fixture.event("StopFailure", at: 1, ["error": "rate_limit"])])
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastError, "rate_limit")
        SessionReducer.apply(Fixture.event("UserPromptSubmit", at: 2), to: &session)
        XCTAssertNil(session.lastError)
    }

    func testSessionEndReasons() {
        XCTAssertEqual(run([Fixture.event("SessionEnd", ["reason": "clear"])]).state, .ended(.clear))
        XCTAssertEqual(run([Fixture.event("SessionEnd", ["reason": "prompt_input_exit"])]).state,
                       .ended(.exit(reason: "prompt_input_exit")))
    }

    func testEndedSessionIgnoresLateEventsAndRevivesOnResume() {
        var session = run([Fixture.event("SessionEnd", ["reason": "other"]),
                           Fixture.event("PostToolUse", at: 1),
                           Fixture.event("Stop", at: 1)])
        XCTAssertEqual(session.state, .ended(.exit(reason: "other")))

        SessionReducer.apply(Fixture.event("SessionStart", at: 100, pid: 5000, ["source": "resume"]), to: &session)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.process?.pid, 5000)
    }

    func testProcessKeepsTtyForSamePidAndResetsOnNewPid() {
        var session = run([Fixture.event("SessionStart", tty: "ttys003"), Fixture.event("Stop", at: 1)])
        XCTAssertEqual(session.process?.tty, "ttys003")
        XCTAssertEqual(session.process?.since, Fixture.base)

        SessionReducer.apply(Fixture.event("SessionStart", at: 50, pid: 5000), to: &session)
        XCTAssertNil(session.process?.tty)
        XCTAssertEqual(session.process?.since, Fixture.base.addingTimeInterval(50))
    }

    func testMarkProcessGone() {
        var session = run([Fixture.event("UserPromptSubmit")])
        SessionReducer.markProcessGone(&session, at: Fixture.base.addingTimeInterval(10))
        XCTAssertEqual(session.state, .ended(.processGone))
    }

    func testTimelineIsCapped() {
        let events = (0..<(Session.timelineLimit + 20)).map { Fixture.event("UserPromptSubmit", at: Double($0), ["prompt": "\($0)"]) }
        let session = run(events)
        XCTAssertEqual(session.timeline.count, Session.timelineLimit)
        XCTAssertEqual(session.timeline.last?.text, "\(Session.timelineLimit + 19)")
        XCTAssertEqual(session.firstPrompt, "0")
    }
}
