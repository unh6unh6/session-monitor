import SwiftUI

/// Everything known about one session: state, recap, last exchange, timeline, process info.
struct SessionDetail: View {
    let session: Session
    let store: SessionStore
    let navigation: Navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = session.lastError {
                    Label("API 오류: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                section("Recap") {
                    if let recap = session.recap {
                        Text(recap).textSelection(.enabled)
                    } else {
                        Text("recap이 없습니다. 세션에서 /session-monitor:recap 을 실행하면 생깁니다.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let prompt = session.lastPrompt {
                    section("마지막 요청") { Text(prompt).textSelection(.enabled) }
                }
                if let response = session.lastResponse, !response.isEmpty {
                    section("마지막 응답") { Text(response).textSelection(.enabled) }
                }
                section("타임라인") { Timeline(entries: session.timeline) }
                section("세션 정보") { info }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(session.displayTitle)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.displayTitle).font(.title2.weight(.semibold)).textSelection(.enabled)
            HStack(spacing: 10) {
                StateBadge(state: session.state)
                StateSince(session: session)
                if session.isRegistered {
                    Text(session.groupLabel).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                } else {
                    Text("미등록").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("작업") { SessionActions(session: session, store: store, navigation: navigation) }
                    .fixedSize()
            }
        }
    }

    private var info: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            infoRow("세션 ID", session.id)
            if let previous = session.previousSessionID { infoRow("이전 세션", previous) }
            if let cwd = session.cwd { infoRow("경로", cwd) }
            if let process = session.process {
                infoRow("PID", "\(process.pid)")
                if let tty = process.tty { infoRow("TTY", tty) }
                if !process.terminal.program.isEmpty { infoRow("터미널", process.terminal.program) }
            }
            infoRow("시작", session.startedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.callout)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct Timeline: View {
    static let visible = 50
    let entries: [TimelineEntry]

    var body: some View {
        if entries.isEmpty {
            Text("기록이 없습니다").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entries.suffix(Self.visible).reversed().enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            .fixedSize()
                            .frame(minWidth: 44, alignment: .leading)
                        Text(Self.label(entry.kind)).font(.caption.weight(.semibold))
                            .foregroundStyle(Self.color(entry.kind))
                            .frame(width: 56, alignment: .leading)
                        Text(entry.text).font(.callout).lineLimit(3).textSelection(.enabled)
                    }
                }
                if entries.count > Self.visible {
                    Text("이전 기록 \(entries.count - Self.visible)건 생략").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func label(_ kind: TimelineEntry.Kind) -> String {
        switch kind {
        case .started: return "시작"
        case .prompt: return "요청"
        case .response: return "응답"
        case .needsResponse: return "응답 필요"
        case .error: return "오류"
        case .ended: return "종료"
        }
    }

    static func color(_ kind: TimelineEntry.Kind) -> Color {
        switch kind {
        case .prompt: return .blue
        case .response: return .green
        case .needsResponse: return .orange
        case .error: return .red
        case .started, .ended: return .secondary
        }
    }
}
