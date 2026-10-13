import SwiftUI

/// Display rules shared by the menu bar and the main window. Kept free of views so they can be tested.
extension SessionState {
    var label: String {
        switch self {
        case .working: return "생성중"
        case .idle: return "응답 완료"
        case .needsResponse(.permission): return "권한 요청"
        case .needsResponse(.question): return "질문"
        case .needsResponse(.other): return "응답 필요"
        case .ended(.clear): return "종료(clear)"
        case .ended: return "종료"
        }
    }

    var symbol: String {
        switch self {
        case .working: return "ellipsis.circle.fill"
        case .idle: return "checkmark.circle.fill"
        case .needsResponse: return "exclamationmark.circle.fill"
        case .ended: return "stop.circle"
        }
    }

    var color: Color {
        switch self {
        case .working: return .blue
        case .idle: return .green
        case .needsResponse: return .orange
        case .ended: return .secondary
        }
    }

    /// Lower sorts first: what needs the user comes on top.
    var sortRank: Int {
        switch self {
        case .needsResponse: return 0
        case .working: return 1
        case .idle: return 2
        case .ended: return 3
        }
    }
}

extension Session {
    /// Claude's session title (e.g. from /rename), else the first prompt, else the id.
    var displayTitle: String {
        for candidate in [title, firstPrompt] {
            if let line = candidate?.split(whereSeparator: \.isNewline).first {
                let text = line.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return String(text.prefix(80)) }
            }
        }
        return String(id.prefix(8))
    }

    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    var groupLabel: String { group ?? SidebarItem.ungroupedLabel }

    static func displayOrder(_ lhs: Session, _ rhs: Session) -> Bool {
        if lhs.state.sortRank != rhs.state.sortRank { return lhs.state.sortRank < rhs.state.sortRank }
        return lhs.updatedAt > rhs.updatedAt
    }
}

/// Sidebar selection in the main window.
enum SidebarItem: Hashable {
    case all
    case group(String)
    case ungrouped
    case unregistered

    static let ungroupedLabel = "미분류"

    var title: String {
        switch self {
        case .all: return "전체"
        case .group(let name): return name
        case .ungrouped: return Self.ungroupedLabel
        case .unregistered: return "미등록"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .group: return "folder"
        case .ungrouped: return "tray"
        case .unregistered: return "circle.dashed"
        }
    }

    /// Sessions shown for this item, in display order.
    @MainActor
    func sessions(in store: SessionStore, includeEnded: Bool) -> [Session] {
        let source: [Session]
        switch self {
        case .all: source = Array(store.sessions.values)
        case .group(let name): source = store.sessions.values.filter { $0.group == name }
        case .ungrouped: source = store.sessions.values.filter { $0.group == nil }
        case .unregistered: source = Array(store.unregistered.values)
        }
        return source.filter { includeEnded || !$0.state.isEnded }.sorted(by: Session.displayOrder)
    }
}

/// A group's sessions as shown under one header in the "전체" list.
struct SessionSection: Identifiable, Equatable {
    /// nil for 미분류.
    let group: String?
    let sessions: [Session]

    var id: String { group.map { "group:\($0)" } ?? "ungrouped" }
    var title: String { group ?? SidebarItem.ungroupedLabel }

    /// Splits sessions by group: groups by name, 미분류 last, display order inside each.
    static func byGroup(_ sessions: [Session]) -> [SessionSection] {
        let grouped = Dictionary(grouping: sessions, by: \.group)
        let names = grouped.keys.compactMap { $0 }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var sections = names.map { SessionSection(group: $0, sessions: grouped[$0]!.sorted(by: Session.displayOrder)) }
        if let ungrouped = grouped[nil] {
            sections.append(SessionSection(group: nil, sessions: ungrouped.sorted(by: Session.displayOrder)))
        }
        return sections
    }
}

/// Counts for the menu bar badge.
struct StatusSummary: Equatable {
    var needsResponse = 0
    var working = 0
    var idle = 0

    init(_ sessions: some Sequence<Session>) {
        for session in sessions {
            switch session.state {
            case .needsResponse: needsResponse += 1
            case .working: working += 1
            case .idle: idle += 1
            case .ended: break
            }
        }
    }
}
