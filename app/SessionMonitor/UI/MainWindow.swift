import SwiftUI

struct MainWindow: View {
    static let id = "main"

    let store: SessionStore
    @Bindable var navigation: Navigation
    @AppStorage("showEndedSessions") private var showEnded = true
    @State private var newGroupName = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, navigation: navigation, showEnded: showEnded)
                .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } content: {
            SessionList(store: store, navigation: navigation, showEnded: showEnded)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if let id = navigation.sessionID, let session = store.sessions[id] ?? store.unregistered[id] {
                SessionDetail(session: session, store: store, navigation: navigation)
            } else {
                Text("세션을 선택하세요").foregroundStyle(.secondary)
            }
        }
        .toolbar {
            Toggle(isOn: $showEnded) { Label("종료 세션 표시", systemImage: "stop.circle") }
                .help("종료된 세션을 목록에 표시")
        }
        .alert("새 그룹", isPresented: Binding(
            get: { navigation.newGroupSessionID != nil },
            set: { if !$0 { navigation.newGroupSessionID = nil } }
        )) {
            TextField("그룹 이름", text: $newGroupName)
            Button("취소", role: .cancel) { newGroupName = "" }
            Button("확인") { createGroup() }
        } message: {
            Text("'/'와 줄바꿈은 쓸 수 없습니다.")
        }
        // Menu bar app: show a Dock icon only while this window is open.
        .onAppear {
            navigation.mainWindowVisible = true
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            navigation.mainWindowVisible = false
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func createGroup() {
        let name = newGroupName
        newGroupName = ""
        guard let id = navigation.newGroupSessionID else { return }
        perform {
            if store.sessions[id] != nil { try store.setGroup(id, group: name) }
            else { try store.register(id, group: name) }
        }
        if let session = store.sessions[id] { navigation.show(session) }
    }
}

private struct Sidebar: View {
    let store: SessionStore
    @Bindable var navigation: Navigation
    let showEnded: Bool

    var body: some View {
        List(selection: $navigation.sidebar) {
            Section("세션") {
                row(.all)
                ForEach(store.groups, id: \.self) { row(.group($0)) }
                row(.ungrouped)
            }
            Section {
                row(.unregistered)
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        let sessions = item.sessions(in: store, includeEnded: false)
        let needsResponse = sessions.contains(where: \.state.needsResponse)
        return Label {
            Text(item.title)
        } icon: {
            // Orange icon flags a group with a session waiting for the user.
            Image(systemName: needsResponse ? "exclamationmark.circle.fill" : item.symbol)
                .foregroundStyle(needsResponse ? Color.orange : Color.accentColor)
        }
        .badge(sessions.count)
        .tag(item)
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, on: item)
            }
    }

    /// Dragging a session onto a group (or 미분류) moves it there; unregistered sessions get registered.
    private func drop(_ ids: [String], on item: SidebarItem) -> Bool {
        let group: String?
        switch item {
        case .group(let name): group = name
        case .ungrouped: group = nil
        case .all, .unregistered: return false
        }
        for id in ids {
            perform {
                if store.sessions[id] != nil { try store.setGroup(id, group: group) }
                else if store.unregistered[id] != nil { try store.register(id, group: group) }
            }
        }
        return true
    }
}

private struct SessionList: View {
    let store: SessionStore
    @Bindable var navigation: Navigation
    let showEnded: Bool

    var body: some View {
        let item = navigation.sidebar ?? .all
        let sessions = item.sessions(in: store, includeEnded: showEnded || item == .unregistered)
        List(selection: $navigation.sessionID) {
            if item == .all {
                ForEach(SessionSection.byGroup(sessions)) { section in
                    Section {
                        rows(section.sessions)
                    } header: {
                        Text("\(section.title) · \(section.sessions.count)")
                    }
                }
            } else {
                rows(sessions)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let session = store.sessions[id] ?? store.unregistered[id] {
                SessionActions(session: session, store: store, navigation: navigation)
            }
        } primaryAction: { ids in
            // Double-click (or Return) jumps to the session's terminal.
            if let id = ids.first, let session = store.sessions[id] ?? store.unregistered[id] {
                TerminalNavigator.focus(session)
            }
        }
        .overlay {
            if sessions.isEmpty {
                if store.sessions.isEmpty && item != .unregistered {
                    EmptyState(store: store).padding(24)
                } else {
                    Text(item == .unregistered ? "미등록 세션이 없습니다" : "세션이 없습니다").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(item.title)
    }

    private func rows(_ sessions: [Session]) -> some View {
        ForEach(sessions) { session in
            SessionRow(session: session, showsGroup: false)
                .tag(session.id)
                .draggable(session.id)
        }
    }
}
