import SwiftUI

/// Menu bar icon: needs-response count first, then working count.
struct MenuBarLabel: View {
    let summary: StatusSummary
    let navigation: Navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        icon.onChange(of: navigation.windowRequest) {
            openWindow(id: MainWindow.id)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if summary.needsResponse > 0 {
            Label("\(summary.needsResponse)", systemImage: "exclamationmark.bubble.fill")
                .labelStyle(.titleAndIcon)
        } else if summary.working > 0 {
            Label("\(summary.working)", systemImage: "ellipsis.bubble.fill")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "bubble.left.and.bubble.right")
        }
    }
}

/// Popover from the menu bar: active registered sessions, most urgent first.
struct MenuBarView: View {
    static let maxRows = 12

    let store: SessionStore
    let navigation: Navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let active = store.sessions.values.filter { !$0.state.isEnded }.sorted(by: Session.displayOrder)
        let summary = StatusSummary(active)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Session Monitor").font(.headline)
                Spacer()
                count(summary.needsResponse, "응답 필요", .orange)
                count(summary.working, "생성중", .blue)
                count(summary.idle, "완료", .green)
            }
            .padding(12)

            Divider()

            if active.isEmpty {
                EmptyState(store: store).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(active.prefix(Self.maxRows)) { session in
                            Button { open(session) } label: {
                                SessionRow(session: session)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if active.count > Self.maxRows {
                            Text("외 \(active.count - Self.maxRows)개").font(.caption).foregroundStyle(.secondary).padding(8)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }

            Divider()

            HStack {
                Button("메인 윈도우 열기") { openMain() }
                NotificationSettingsMenu()
                if !store.unregistered.isEmpty {
                    Text("미등록 \(store.unregistered.count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 380)
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        Text("\(label) \(value)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(value > 0 ? color : .secondary)
    }

    private func open(_ session: Session) {
        navigation.show(session)
        openMain()
    }

    private func openMain() {
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Shown when there is nothing to list; explains how to get sessions in.
struct EmptyState: View {
    let store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.pluginDetected {
                Text("등록된 세션이 없습니다").font(.headline)
                Text("추적할 Claude Code 세션에서 실행하세요:").foregroundStyle(.secondary)
                Text("/session-monitor:register [그룹]").font(.body.monospaced()).textSelection(.enabled)
            } else {
                Text("Claude Code 플러그인을 설치하세요").font(.headline)
                Text("Claude Code에서 아래 두 줄을 실행하면 세션 상태가 여기에 표시됩니다.").foregroundStyle(.secondary)
                Text("/plugin marketplace add unh6unh6/session-monitor\n/plugin install session-monitor@session-monitor")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Per-kind notification toggles (read by Notifier via NotificationPolicy.Settings.load()).
struct NotificationSettingsMenu: View {
    @AppStorage(NotificationPolicy.Settings.needsResponseKey) private var needsResponse = true
    @AppStorage(NotificationPolicy.Settings.doneKey) private var done = true

    var body: some View {
        Menu {
            Toggle("응답 필요 알림", isOn: $needsResponse)
            Toggle("응답 완료 알림", isOn: $done)
        } label: {
            Image(systemName: needsResponse || done ? "bell" : "bell.slash")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("알림 설정")
    }
}
