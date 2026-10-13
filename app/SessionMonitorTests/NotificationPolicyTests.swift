import XCTest
@testable import SessionMonitor

final class NotificationPolicyTests: XCTestCase {
    private let now = Fixture.base.addingTimeInterval(10)
    private let all = NotificationPolicy.Settings()

    private func session(_ state: SessionState, registered: Bool = true, changedAgo: TimeInterval = 5) -> Session {
        var session = Session(id: Fixture.sessionA, isRegistered: registered, date: Fixture.base)
        session.state = state
        session.stateChangedAt = now.addingTimeInterval(-changedAgo)
        session.group = "이슈A"
        session.cwd = "/Users/me/work/api"
        session.firstPrompt = "결제 리팩토링"
        return session
    }

    func testPermissionRequestNotifies() throws {
        let content = try XCTUnwrap(NotificationPolicy.content(
            for: session(.needsResponse(.permission(tool: "Bash"))), from: .working, now: now, settings: all))
        XCTAssertEqual(content.kind, .needsResponse)
        XCTAssertEqual(content.title, "권한 요청 — 결제 리팩토링")
        XCTAssertEqual(content.subtitle, "이슈A · api")
        XCTAssertEqual(content.body, "Bash 실행 권한을 요청합니다")
        XCTAssertEqual(content.sessionID, Fixture.sessionA)
    }

    func testQuestionNotifiesOnceNotOnRepeatNeedsResponse() {
        XCTAssertNotNil(NotificationPolicy.content(for: session(.needsResponse(.question)), from: .working, now: now, settings: all))
        XCTAssertNil(NotificationPolicy.content(for: session(.needsResponse(.other(message: "m"))),
                                                from: .needsResponse(.question), now: now, settings: all))
    }

    func testFinishedTurnNotifiesWithResponseSummary() throws {
        var s = session(.idle)
        s.lastResponse = "첫 줄입니다.\n\n  둘째 줄  \n"
        let content = try XCTUnwrap(NotificationPolicy.content(for: s, from: .working, now: now, settings: all))
        XCTAssertEqual(content.kind, .done)
        XCTAssertEqual(content.body, "첫 줄입니다. 둘째 줄")

        s.lastError = "rate_limit"
        XCTAssertEqual(NotificationPolicy.content(for: s, from: .working, now: now, settings: all)?.body, "API 오류: rate_limit")
    }

    func testIdleFromStartOrResumeDoesNotNotify() {
        XCTAssertNil(NotificationPolicy.content(for: session(.idle), from: .ended(.processGone), now: now, settings: all))
        XCTAssertNil(NotificationPolicy.content(for: session(.idle), from: .idle, now: now, settings: all))
    }

    func testWorkingAndEndedDoNotNotify() {
        XCTAssertNil(NotificationPolicy.content(for: session(.working), from: .idle, now: now, settings: all))
        XCTAssertNil(NotificationPolicy.content(for: session(.ended(.clear)), from: .idle, now: now, settings: all))
    }

    func testSettingsDisableEachKind() {
        let noNeeds = NotificationPolicy.Settings(needsResponse: false, done: true)
        let noDone = NotificationPolicy.Settings(needsResponse: true, done: false)
        XCTAssertNil(NotificationPolicy.content(for: session(.needsResponse(.question)), from: .working, now: now, settings: noNeeds))
        XCTAssertNotNil(NotificationPolicy.content(for: session(.idle), from: .working, now: now, settings: noNeeds))
        XCTAssertNil(NotificationPolicy.content(for: session(.idle), from: .working, now: now, settings: noDone))
    }

    func testUnregisteredAndStaleTransitionsAreSkipped() {
        XCTAssertNil(NotificationPolicy.content(for: session(.idle, registered: false), from: .working, now: now, settings: all))
        XCTAssertNil(NotificationPolicy.content(for: session(.idle, changedAgo: NotificationPolicy.freshness + 1),
                                                from: .working, now: now, settings: all))
    }

    func testSummaryIsCut() {
        let long = String(repeating: "가", count: 500)
        let summary = NotificationPolicy.summary(long)
        XCTAssertEqual(summary.count, NotificationPolicy.bodyLimit)
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    func testSettingsDefaultToOn() {
        let defaults = UserDefaults(suiteName: "sm-test-\(UUID().uuidString)")!
        XCTAssertEqual(NotificationPolicy.Settings.load(from: defaults), NotificationPolicy.Settings())
        defaults.set(false, forKey: NotificationPolicy.Settings.doneKey)
        XCTAssertEqual(NotificationPolicy.Settings.load(from: defaults).done, false)
    }
}
