import XCTest
@testable import SessionMonitor

final class ProcessProbeTests: XCTestCase {
    func testCurrentProcessIsAlive() {
        XCTAssertTrue(ProcessProbe().isAlive(pid: getpid(), startedBefore: Date()))
    }

    func testReusedPidIsNotAlive() {
        // Our process started after this date, so it can't be the session's process.
        XCTAssertFalse(ProcessProbe().isAlive(pid: getpid(), startedBefore: Date(timeIntervalSince1970: 0)))
    }

    func testMissingPidIsNotAlive() {
        XCTAssertFalse(ProcessProbe().isAlive(pid: 99_999_999, startedBefore: Date()))
        XCTAssertFalse(ProcessProbe().isAlive(pid: 0, startedBefore: Date()))
    }
}
