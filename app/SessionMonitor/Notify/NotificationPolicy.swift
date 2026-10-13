import Foundation

/// Which state changes become macOS notifications, and what they say (docs/plan.md decision #8).
enum NotificationPolicy {
    enum Kind: String, Equatable {
        case needsResponse
        case done
    }

    struct Settings: Equatable {
        var needsResponse = true
        var done = true

        static let needsResponseKey = "notifyNeedsResponse"
        static let doneKey = "notifyDone"

        static func load(from defaults: UserDefaults = .standard) -> Settings {
            Settings(needsResponse: defaults.object(forKey: needsResponseKey) as? Bool ?? true,
                     done: defaults.object(forKey: doneKey) as? Bool ?? true)
        }
    }

    struct Content: Equatable {
        var kind: Kind
        var sessionID: String
        var title: String
        var subtitle: String
        var body: String
    }

    /// Transitions older than this are backlog (e.g. spool ingested at app launch), not news.
    static let freshness: TimeInterval = 120
    static let bodyLimit = 200

    /// The notification for a registered session that went from `before` to `session.state`, if any.
    static func content(for session: Session, from before: SessionState, now: Date, settings: Settings) -> Content? {
        guard session.isRegistered, now.timeIntervalSince(session.stateChangedAt) <= freshness else { return nil }

        let kind: Kind
        let body: String
        switch session.state {
        case .needsResponse(let need):
            guard settings.needsResponse, !before.needsResponse else { return nil }
            kind = .needsResponse
            switch need {
            case .permission(let tool): body = tool.isEmpty ? "권한 승인이 필요합니다" : "\(tool) 실행 권한을 요청합니다"
            case .question: body = "Claude가 질문했습니다"
            case .other(let message): body = message.isEmpty ? "입력이 필요합니다" : message
            }
        case .idle:
            // Only a finished turn counts; SessionStart/resume also land in idle.
            guard settings.done, before == .working || before.needsResponse else { return nil }
            kind = .done
            if let error = session.lastError {
                body = "API 오류: \(error)"
            } else {
                body = session.lastResponse.map(Self.summary) ?? ""
            }
        case .working, .ended:
            return nil
        }

        let subtitle = [session.groupLabel, session.projectName].compactMap { $0 }.joined(separator: " · ")
        return Content(kind: kind, sessionID: session.id,
                       title: "\(session.state.label) — \(session.displayTitle)",
                       subtitle: subtitle, body: body)
    }

    /// First lines of a response, collapsed and cut to `bodyLimit`.
    static func summary(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.count > bodyLimit ? String(collapsed.prefix(bodyLimit - 1)) + "…" : collapsed
    }
}
