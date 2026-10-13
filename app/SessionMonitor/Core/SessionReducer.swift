import Foundation

/// Pure state machine from hook events to session state (DECISIONS.md D4, D5, D9).
///
/// SessionStart          → idle
/// UserPromptSubmit      → working
/// PermissionRequest     → needsResponse
/// Notification(prompt)  → needsResponse (only while working; it trails PermissionRequest by ~6s)
/// PostToolUse(Failure)  → working, only when leaving needsResponse (async, may arrive late)
/// Stop / StopFailure    → idle
/// SessionEnd            → ended
enum SessionReducer {
    static func apply(_ event: HookEvent, to session: inout Session) {
        let date = event.timestamp
        session.updatedAt = max(session.updatedAt, date)

        // An ended session only comes back through SessionStart (resume); anything else is a
        // late async hook from the old process.
        if session.state.isEnded, event.kind != .sessionStart, event.kind != .userPromptSubmit {
            return
        }

        if let cwd = event["cwd"], !cwd.isEmpty { session.cwd = cwd }
        if let title = event["session_title"], !title.isEmpty { session.title = title }
        if let pid = event.pid { updateProcess(&session, pid: pid, event: event) }

        switch event.kind {
        case .sessionStart:
            let source = event["source"] ?? "startup"
            transition(&session, to: .idle, at: date)
            session.appendTimeline(TimelineEntry(date: date, kind: .started, text: source))

        case .userPromptSubmit:
            let prompt = event["prompt"] ?? ""
            if session.firstPrompt == nil { session.firstPrompt = prompt }
            session.lastPrompt = prompt
            session.lastError = nil
            transition(&session, to: .working, at: date)
            session.appendTimeline(TimelineEntry(date: date, kind: .prompt, text: prompt))

        case .permissionRequest:
            let tool = event["tool_name"] ?? ""
            let need: SessionState.NeedsResponse =
                tool == "AskUserQuestion" ? .question : .permission(tool: tool)
            enterNeedsResponse(&session, need, at: date)

        case .notification:
            switch event["notification_type"] {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                guard session.state == .working else { break }
                enterNeedsResponse(&session, .other(message: event["message"] ?? ""), at: date)
            default:
                break
            }

        case .postToolUse, .postToolUseFailure:
            if session.state.needsResponse {
                transition(&session, to: .working, at: date)
            }

        case .stop:
            let message = event["last_assistant_message"] ?? ""
            session.lastResponse = message
            transition(&session, to: .idle, at: date)
            session.appendTimeline(TimelineEntry(date: date, kind: .response, text: message))

        case .stopFailure:
            let error = event["error"] ?? "unknown"
            session.lastError = error
            transition(&session, to: .idle, at: date)
            session.appendTimeline(TimelineEntry(date: date, kind: .error, text: error))

        case .sessionEnd:
            let reason = event["reason"] ?? "other"
            transition(&session, to: .ended(reason == "clear" ? .clear : .exit(reason: reason)), at: date)
            session.appendTimeline(TimelineEntry(date: date, kind: .ended, text: reason))

        case nil:
            break
        }
    }

    /// Marks a session whose process disappeared without SessionEnd.
    static func markProcessGone(_ session: inout Session, at date: Date) {
        guard !session.state.isEnded else { return }
        transition(&session, to: .ended(.processGone), at: date)
        session.appendTimeline(TimelineEntry(date: date, kind: .ended, text: "process gone"))
    }

    private static func enterNeedsResponse(_ session: inout Session, _ need: SessionState.NeedsResponse, at date: Date) {
        transition(&session, to: .needsResponse(need), at: date)
        let text: String
        switch need {
        case .permission(let tool): text = tool
        case .question: text = "AskUserQuestion"
        case .other(let message): text = message
        }
        session.appendTimeline(TimelineEntry(date: date, kind: .needsResponse, text: text))
    }

    private static func transition(_ session: inout Session, to state: SessionState, at date: Date) {
        guard session.state != state else { return }
        session.state = state
        session.stateChangedAt = date
    }

    // tty is only sent on SessionStart, so keep it while the pid stays the same.
    private static func updateProcess(_ session: inout Session, pid: Int32, event: HookEvent) {
        let previous = session.process
        let tty = event.tty ?? (previous?.pid == pid ? previous?.tty : nil)
        let terminal = event.terminal.program.isEmpty && previous?.pid == pid
            ? previous?.terminal ?? event.terminal
            : event.terminal
        let since = previous?.pid == pid ? min(previous?.since ?? event.timestamp, event.timestamp) : event.timestamp
        session.process = SessionProcess(pid: pid, tty: tty, terminal: terminal, since: since)
    }
}
