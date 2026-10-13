import SwiftUI

struct StateBadge: View {
    let state: SessionState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.color)
            .labelStyle(.titleAndIcon)
    }
}

/// One session in a list: state, title, project/group, last prompt and time in state.
struct SessionRow: View {
    let session: Session
    var showsGroup = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.state.symbol)
                .foregroundStyle(session.state.color)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    StateSince(session: session)
                }
                HStack(spacing: 6) {
                    Text(session.state.label).foregroundStyle(session.state.color)
                    if showsGroup, session.isRegistered { Text("· \(session.groupLabel)") }
                    if let project = session.projectName { Text("· \(project)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let prompt = session.lastPrompt, prompt != session.displayTitle {
                    Text(prompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(session.isRegistered && !session.state.isEnded ? 1 : 0.55)
    }
}

/// Time since the session entered its current state ("3분"), or when it ended.
struct StateSince: View {
    let session: Session

    var body: some View {
        if session.state.isEnded {
            Text(session.stateChangedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption2).foregroundStyle(.tertiary)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.elapsed(from: session.stateChangedAt, to: context.date))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        return formatter
    }()

    /// Coarse elapsed time: "방금" under a minute, else the largest unit ("47분", "3시간").
    static func elapsed(from start: Date, to now: Date) -> String {
        let interval = now.timeIntervalSince(start)
        guard interval >= 60 else { return "방금" }
        return formatter.string(from: interval) ?? ""
    }
}

/// Context/menu actions for a session: register, move between groups, unregister.
/// "새 그룹…" is asked by the main window (menus can't host alerts).
struct SessionActions: View {
    let session: Session
    let store: SessionStore
    let navigation: Navigation

    var body: some View {
        if session.isRegistered {
            Menu("그룹 이동") { groupItems { try store.setGroup(session.id, group: $0) } }
            Divider()
            Button(session.state.isEnded ? "목록에서 삭제" : "등록 해제", role: .destructive) {
                perform { try store.unregister(session.id) }
            }
        } else {
            Menu("등록") { groupItems { try store.register(session.id, group: $0) } }
        }
    }

    @ViewBuilder
    private func groupItems(_ apply: @escaping (String?) throws -> Void) -> some View {
        ForEach(store.groups, id: \.self) { name in
            Button(name) { perform { try apply(name) } }
                .disabled(session.isRegistered && session.group == name)
        }
        if !store.groups.isEmpty { Divider() }
        Button("새 그룹…") { navigation.newGroupSessionID = session.id }
        Button(SidebarItem.ungroupedLabel) { perform { try apply(nil) } }
            .disabled(session.isRegistered && session.group == nil)
    }
}

/// Runs a store action; failures (invalid name, file errors) just beep.
@MainActor
func perform(_ action: () throws -> Void) {
    do { try action() } catch { NSSound.beep() }
}
