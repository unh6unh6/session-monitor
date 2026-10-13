import Foundation

/// Terminal environment captured by the hook (docs/plan.md §3.5).
struct TerminalInfo: Codable, Equatable {
    var program: String = ""
    var session: String = ""
    var iterm: String = ""
    var tmux: String = ""
    var tmuxPane: String = ""

    enum CodingKeys: String, CodingKey {
        case program, session, iterm, tmux
        case tmuxPane = "tmux_pane"
    }
}

/// One spool/seen record written by plugin/scripts/hook.sh (DECISIONS.md D9).
/// The raw hook input is kept loosely typed: only string fields the app uses are extracted,
/// so new Claude Code fields never break parsing.
struct HookEvent: Equatable {
    enum Kind: String {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case sessionEnd = "SessionEnd"
    }

    let sessionID: String
    let name: String
    let timestamp: Date
    let pid: Int32?
    let tty: String?
    let terminal: TerminalInfo
    let fields: [String: String]

    var kind: Kind? { Kind(rawValue: name) }
    subscript(field: String) -> String? { fields[field] }

    static let extractedFields = [
        "cwd", "transcript_path", "permission_mode", "source", "reason", "prompt",
        "last_assistant_message", "tool_name", "notification_type", "message",
        "error", "error_details", "session_title",
    ]

    /// Parses a record. `fallbackDate` is used when the record has no parseable `ts`.
    static func parse(_ data: Data, fallbackDate: Date = Date()) -> HookEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let input = root["input"] as? [String: Any],
              let sessionID = input["session_id"] as? String, !sessionID.isEmpty,
              let name = input["hook_event_name"] as? String
        else { return nil }

        var fields: [String: String] = [:]
        for key in extractedFields {
            if let value = input[key] as? String { fields[key] = value }
        }
        var terminal = TerminalInfo()
        if let term = root["term"] as? [String: Any],
           let termData = try? JSONSerialization.data(withJSONObject: term) {
            terminal = (try? JSONDecoder().decode(TerminalInfo.self, from: termData)) ?? TerminalInfo()
        }
        let tty = (root["tty"] as? String).flatMap { $0.isEmpty || $0 == "??" ? nil : $0 }

        return HookEvent(
            sessionID: sessionID,
            name: name,
            timestamp: (root["ts"] as? String).flatMap(Self.parseTimestamp) ?? fallbackDate,
            pid: (root["pid"] as? NSNumber).map { $0.int32Value },
            tty: tty,
            terminal: terminal,
            fields: fields
        )
    }

    // hook.sh writes `date '+%Y-%m-%dT%H:%M:%S%z'`, e.g. 2026-10-13T22:54:50+0900.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    static func parseTimestamp(_ string: String) -> Date? {
        timestampFormatter.date(from: string)
    }
}
