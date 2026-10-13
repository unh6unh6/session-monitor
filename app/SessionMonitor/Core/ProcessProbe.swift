import Darwin
import Foundation

/// Tells whether a session's claude process is still running.
protocol ProcessProbing {
    /// `startedBefore`: the session's latest SessionStart. A live pid whose process started
    /// later is a reused pid, not our claude process.
    func isAlive(pid: Int32, startedBefore: Date) -> Bool
}

struct ProcessProbe: ProcessProbing {
    /// Slack for clock/second rounding between the process start time and the hook timestamp.
    static let startTolerance: TimeInterval = 5

    func isAlive(pid: Int32, startedBefore: Date) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) != 0 && errno != EPERM { return false }
        guard let started = Self.startTime(of: pid) else { return true }
        return started <= startedBefore.addingTimeInterval(Self.startTolerance)
    }

    static func startTime(of pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
