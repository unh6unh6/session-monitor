import SwiftUI
import XCTest
@testable import SessionMonitor

/// Renders the UI with sample sessions to PNG files for visual review.
/// Skipped unless SNAPSHOT_DIR is set: `TEST_RUNNER_SNAPSHOT_DIR=/tmp/snaps xcodebuild test ...`
@MainActor
final class SnapshotTests: XCTestCase {
    func testRenderSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SNAPSHOT_DIR to render snapshots")
        }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let root = Fixture.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeSampleStore(root: root)
        let navigation = Navigation()

        try render(MenuBarView(store: store, navigation: navigation), size: CGSize(width: 380, height: 420),
                   to: out.appendingPathComponent("menubar.png"))

        navigation.sessionID = "11111111-aaaa-4000-8000-000000000001"
        try render(MainWindow(store: store, navigation: navigation), size: CGSize(width: 1100, height: 700),
                   to: out.appendingPathComponent("main.png"))

        navigation.sidebar = .unregistered
        navigation.sessionID = nil
        try render(MainWindow(store: store, navigation: navigation), size: CGSize(width: 1100, height: 500),
                   to: out.appendingPathComponent("main-unregistered.png"))
    }

    private func makeSampleStore(root: URL) throws -> SessionStore {
        let files = MonitorFiles(root: root)
        let samples: [(id: String, group: String?, cwd: String, events: [(String, [String: Any])])] = [
            ("11111111-aaaa-4000-8000-000000000001", "이슈A", "/Users/me/work/api", [
                ("SessionStart", ["source": "startup"]),
                ("UserPromptSubmit", ["prompt": "결제 서비스 레이어를 분리해줘"]),
                ("Stop", ["last_assistant_message": "PaymentService를 분리했습니다. 테스트를 추가할까요?"]),
                ("UserPromptSubmit", ["prompt": "응 테스트도 추가해줘"]),
                ("PermissionRequest", ["tool_name": "Bash"]),
            ]),
            ("22222222-bbbb-4000-8000-000000000002", "이슈A", "/Users/me/work/web", [
                ("UserPromptSubmit", ["prompt": "로그인 화면 다크모드 지원", "session_title": "login-dark-mode"]),
            ]),
            ("33333333-cccc-4000-8000-000000000003", "이슈B", "/Users/me/work/infra", [
                ("UserPromptSubmit", ["prompt": "배포 스크립트 점검"]),
                ("Stop", ["last_assistant_message": "점검 완료. 문제 없습니다."]),
            ]),
            ("55555555-eeee-4000-8000-000000000005", nil, "/Users/me/work/old", [
                ("UserPromptSubmit", ["prompt": "오래된 작업"]),
                ("SessionEnd", ["reason": "prompt_input_exit"]),
            ]),
        ]
        for sample in samples {
            try files.register(sample.id, group: sample.group)
            let spool = files.spoolDir.appendingPathComponent(sample.id, isDirectory: true)
            try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
            for (index, event) in sample.events.enumerated() {
                var extra = event.1
                extra["cwd"] = sample.cwd
                let url = spool.appendingPathComponent("\(index).json")
                try Fixture.record(event.0, sample.id, extra: extra).write(to: url)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(index - 300))],
                                                      ofItemAtPath: url.path)
            }
        }
        try files.register("55555555-eeee-4000-8000-000000000005", group: nil)
        let recap = files.sessionsDir.appendingPathComponent("11111111-aaaa-4000-8000-000000000001/recap.md")
        try Data("결제 API 리팩토링 중.\n- 서비스 레이어 분리 완료\n- 다음: 테스트 보강".utf8).write(to: recap)

        try FileManager.default.createDirectory(at: files.seenDir, withIntermediateDirectories: true)
        try Fixture.record("UserPromptSubmit", "44444444-dddd-4000-8000-000000000004",
                           extra: ["prompt": "README 오타 수정", "cwd": "/Users/me/work/misc"])
            .write(to: files.seenDir.appendingPathComponent("44444444-dddd-4000-8000-000000000004.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("pids"), withIntermediateDirectories: true)

        let store = SessionStore(files: files, stateURL: root.appendingPathComponent("state.json"), probe: FakeProbe())
        store.refresh()
        return store
    }

    private func render(_ view: some View, size: CGSize, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
