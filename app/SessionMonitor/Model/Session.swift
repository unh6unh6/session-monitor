import Foundation

/// The four states shown in the app (docs/plan.md decision #5).
enum SessionState: Codable, Equatable {
    case working
    case idle
    case needsResponse(NeedsResponse)
    case ended(EndReason)

    enum NeedsResponse: Codable, Equatable {
        case permission(tool: String)
        case question
        case other(message: String)
    }

    enum EndReason: Codable, Equatable {
        case clear
        case exit(reason: String)
        case processGone
    }

    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }

    var needsResponse: Bool {
        if case .needsResponse = self { return true }
        return false
    }
}

/// The claude process currently (or last) hosting a session.
struct SessionProcess: Codable, Equatable {
    var pid: Int32
    var tty: String?
    var terminal: TerminalInfo
    /// First event seen from this pid; the process must have started before it.
    var since: Date
}

struct TimelineEntry: Codable, Equatable {
    enum Kind: String, Codable {
        case started, prompt, response, needsResponse, error, ended
    }

    var date: Date
    var kind: Kind
    var text: String
}

struct Session: Codable, Equatable, Identifiable {
    static let timelineLimit = 300

    let id: String
    var isRegistered: Bool
    var group: String?
    var recap: String?
    var previousSessionID: String?

    var state: SessionState = .idle
    var stateChangedAt: Date
    var cwd: String?
    var title: String?
    var process: SessionProcess?
    var firstPrompt: String?
    var lastPrompt: String?
    var lastResponse: String?
    var lastError: String?
    var timeline: [TimelineEntry] = []
    var startedAt: Date
    var updatedAt: Date

    init(id: String, isRegistered: Bool, date: Date) {
        self.id = id
        self.isRegistered = isRegistered
        self.stateChangedAt = date
        self.startedAt = date
        self.updatedAt = date
    }

    mutating func appendTimeline(_ entry: TimelineEntry) {
        timeline.append(entry)
        if timeline.count > Self.timelineLimit {
            timeline.removeFirst(timeline.count - Self.timelineLimit)
        }
    }
}
