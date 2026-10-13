import XCTest
@testable import SessionMonitor

@MainActor
final class PresentationTests: XCTestCase {
    private func session(_ id: String, _ state: SessionState, updated: TimeInterval = 0, group: String? = nil,
                         registered: Bool = true) -> Session {
        var session = Session(id: id, isRegistered: registered, date: Fixture.base)
        session.state = state
        session.updatedAt = Fixture.base.addingTimeInterval(updated)
        session.group = group
        return session
    }

    func testDisplayOrderPutsNeedsResponseFirstThenRecent() {
        let sessions = [
            session("a", .idle, updated: 50),
            session("b", .ended(.processGone), updated: 99),
            session("c", .working, updated: 10),
            session("d", .needsResponse(.question), updated: 1),
            session("e", .working, updated: 20),
        ]
        XCTAssertEqual(sessions.sorted(by: Session.displayOrder).map(\.id), ["d", "e", "c", "a", "b"])
    }

    func testSectionsByGroupSortNamesAndPutUngroupedLast() {
        let sections = SessionSection.byGroup([
            session("a", .idle, updated: 5, group: "이슈B"),
            session("b", .working, updated: 1),
            session("c", .idle, updated: 9, group: "이슈A"),
            session("d", .needsResponse(.question), updated: 0, group: "이슈B"),
            session("e", .idle, updated: 3, group: "미분류"),
        ])
        XCTAssertEqual(sections.map(\.title), ["미분류", "이슈A", "이슈B", "미분류"])
        XCTAssertEqual(Set(sections.map(\.id)).count, 4, "a group literally named 미분류 doesn't collide")
        XCTAssertEqual(sections[2].sessions.map(\.id), ["d", "a"])
        XCTAssertNil(sections[3].group)
    }

    func testDisplayTitleFallbacks() {
        var s = session("abcdef0123", .idle)
        XCTAssertEqual(s.displayTitle, "abcdef01")
        s.firstPrompt = "\n  첫 줄 요청  \n둘째 줄"
        XCTAssertEqual(s.displayTitle, "첫 줄 요청")
        s.title = "session-monitor"
        XCTAssertEqual(s.displayTitle, "session-monitor")
    }

    func testProjectName() {
        var s = session("a", .idle)
        XCTAssertNil(s.projectName)
        s.cwd = "/Users/me/work/foo"
        XCTAssertEqual(s.projectName, "foo")
    }

    func testStatusSummaryIgnoresEnded() {
        let summary = StatusSummary([session("a", .needsResponse(.question)), session("b", .working),
                                     session("c", .working), session("d", .ended(.clear)), session("e", .idle)])
        XCTAssertEqual(summary.needsResponse, 1)
        XCTAssertEqual(summary.working, 2)
        XCTAssertEqual(summary.idle, 1)
    }

    func testSidebarFilters() throws {
        let root = Fixture.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = MonitorFiles(root: root)
        for (id, group) in [(Fixture.sessionA, "이슈A"), (Fixture.sessionB, nil)] as [(String, String?)] {
            try files.register(id, group: group)
        }
        let store = SessionStore(files: files, stateURL: root.appendingPathComponent("s.json"), probe: FakeProbe())
        store.refresh()

        XCTAssertEqual(SidebarItem.all.sessions(in: store, includeEnded: true).count, 2)
        XCTAssertEqual(SidebarItem.group("이슈A").sessions(in: store, includeEnded: true).map(\.id), [Fixture.sessionA])
        XCTAssertEqual(SidebarItem.ungrouped.sessions(in: store, includeEnded: true).map(\.id), [Fixture.sessionB])
        XCTAssertEqual(store.groups, ["이슈A"])
    }

    func testNavigationShowSwitchesSidebarWhenHidden() {
        let navigation = Navigation()
        navigation.sidebar = .group("이슈A")
        navigation.show(session("x", .idle, group: "이슈B"))
        XCTAssertEqual(navigation.sidebar, .all)
        XCTAssertEqual(navigation.sessionID, "x")

        navigation.sidebar = .group("이슈B")
        navigation.show(session("y", .idle, group: "이슈B"))
        XCTAssertEqual(navigation.sidebar, .group("이슈B"))

        navigation.show(session("z", .idle, registered: false))
        XCTAssertEqual(navigation.sidebar, .unregistered)
    }
}
