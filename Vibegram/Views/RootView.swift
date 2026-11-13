import SwiftUI

enum Palette {
    static let accent = Color(red: 0.15, green: 0.48, blue: 0.40)
    static let canvas = Color("Canvas")
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if store.isReady { ChatShell() } else { LoginView() }
        }
        .tint(Palette.accent)
        .onChange(of: scenePhase, initial: true) { _, phase in store.setSceneActive(phase == .active) }
        .sheet(isPresented: $store.showSettings) { SettingsView() }
        .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct ChatShell: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    var filtered: [Chat] {
        store.sortedChats.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "leaf.fill").foregroundStyle(Palette.accent)
                    Text("Vibegram").font(.title2.weight(.semibold))
                    Spacer()
                }.padding(.horizontal, 20).padding(.vertical, 18)
                List(selection: $store.selectedChatID) {
                    Section("对话 · \(filtered.count)") {
                        ForEach(filtered) { chat in
                            NavigationLink(value: chat.id) { ChatRow(chat: chat, draft: store.draft(for: chat.id), isSelected: store.selectedChatID == chat.id) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $search, prompt: "搜索对话")
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "还没有对话" : "没有找到对话", systemImage: search.isEmpty ? "bubble.left" : "magnifyingglass", description: Text(search.isEmpty ? "等待同步你的 Telegram 对话。" : "试试其他名称。"))
                    }
                }
                HStack(spacing: 8) {
                    Circle().fill(store.isDemo ? Color.orange : Palette.accent).frame(width: 6, height: 6)
                    Text(store.connection).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.showSettings = true } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).accessibilityLabel("设置")
                }.padding(16)
            }
            .navigationTitle("对话")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
        } detail: {
            if let chat = store.selectedChat {
                ConversationView(chat: chat).id(chat.id)
            } else {
                ContentUnavailableView {
                    Label("给对话一点空间", systemImage: "bubble.left.and.bubble.right")
                } description: { Text("选择左侧的对话，开始聊天。") }
            }
        }
        .onChange(of: store.selectedChatID) { previous, id in store.select(id, previous: previous) }
    }
}

struct Avatar: View {
    let chat: Chat
    var selected = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(selected ? Color.white.opacity(0.12) : Palette.accent.opacity(0.10))
            if chat.isChannel { Image(systemName: "megaphone.fill") }
            else { Text(String(chat.title.prefix(1))).font(.title3.weight(.medium)) }
        }
        .foregroundStyle(selected ? .white : Palette.accent).frame(width: 46, height: 46).accessibilityHidden(true)
    }
}

struct ChatRow: View {
    let chat: Chat
    var draft = ""
    var isSelected = false
    var body: some View {
        HStack(spacing: 12) {
            Avatar(chat: chat, selected: isSelected)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(chat.title).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if chat.date != .distantPast { Text(chat.date, style: .time).font(.caption2).foregroundStyle(.secondary) }
                }
                HStack {
                    if !draft.isEmpty {
                        Text("草稿：\(draft)").font(.subheadline).foregroundStyle(isSelected ? Color.white.opacity(0.85) : Palette.accent).lineLimit(1)
                    } else {
                        Text(chat.preview.isEmpty ? "暂无消息" : chat.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if chat.unread > 0 {
                        Text("\(chat.unread)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(Palette.accent, in: Capsule())
                    }
                }
            }
        }.padding(.vertical, 7)
    }
}

struct ConversationView: View {
    @EnvironmentObject private var store: AppStore
    let chat: Chat
    @State private var query = ""
    @State private var showSearch = false
    @State private var followLatest = true
    var items: [Message] { store.messages[chat.id] ?? [] }
    var draft: Binding<String> { Binding(get: { store.draft(for: chat.id) }, set: { store.setDraft($0, chatID: chat.id) }) }
    var visibleItems: [Message] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(term) || (store.senderName(for: $0)?.localizedCaseInsensitiveContains(term) ?? false) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if store.isDemo {
                HStack(spacing: 6) {
                    Image(systemName: "testtube.2")
                    Text("演示空间 · 消息不会发送到 Telegram")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(10).background(.quaternary.opacity(0.4))
            }
            if showSearch {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索已加载的消息或发言者", text: $query).textFieldStyle(.plain).accessibilityLabel("搜索聊天消息")
                    Text("\(visibleItems.count) 条").font(.caption).foregroundStyle(.secondary)
                    Button { query = ""; showSearch = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("关闭消息搜索")
                }.padding(14)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !store.isDemo && !store.exhaustedHistory.contains(chat.id) {
                            Button(store.loadingHistory.contains(chat.id) ? "正在加载…" : "加载更早的消息") {
                                followLatest = false
                                store.loadHistory(chatID: chat.id, older: true)
                            }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.accent)
                                .disabled(store.loadingHistory.contains(chat.id)).padding(.top, 8)
                        }
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, message in
                            if index == 0 || !Calendar.current.isDate(message.date, inSameDayAs: visibleItems[index - 1].date) {
                                Text(message.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 5)
                            }
                            MessageBubble(message: message, senderName: chat.isGroup ? store.senderName(for: message) : nil,
                                          retrying: store.retryingMessages.contains(message.retryKey), retry: { store.retry(message) })
                                .onAppear { store.markVisible(message) }
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
                }
                .background(Palette.canvas)
                .overlay {
                    if visibleItems.isEmpty && !store.loadingHistory.contains(chat.id) {
                        ContentUnavailableView(query.isEmpty ? "开始这段对话" : "没有找到消息", systemImage: query.isEmpty ? "bubble.left" : "magnifyingglass", description: Text(query.isEmpty ? "写下你的第一条消息。" : "仅搜索本机已加载的消息，可加载更早的记录后再试。"))
                            .allowsHitTesting(false)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: items.last?.id) { _, _ in
                    if followLatest && query.isEmpty { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    followLatest = true
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField(store.isDemo ? "写一条演示消息…" : "发送消息…", text: draft, axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.plain).padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.body.bold()).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Palette.accent, in: Circle())
                }.buttonStyle(.plain).disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.sendingChats.contains(chat.id))
                    .accessibilityLabel("发送消息").keyboardShortcut(.return, modifiers: .command)
            }.padding(16)
        }
        .navigationTitle(chat.title)
        .toolbar {
            ToolbarItem {
                Button { showSearch.toggle(); if !showSearch { query = "" } } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("搜索消息").keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem { Button { store.showSettings = true } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("设置") }
        }
    }
    private func send() {
        followLatest = true
        let submitted = draft.wrappedValue
        store.sendText(submitted, chatID: chat.id) { accepted in
            if accepted && store.draft(for: chat.id) == submitted { store.setDraft("", chatID: chat.id); store.flushDrafts() }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    var senderName: String?
    var retrying = false
    var retry: () -> Void = {}
    var body: some View {
        HStack(alignment: .bottom) {
            if message.outgoing { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 7) {
                if let senderName { Text(senderName).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent) }
                Text(message.text).textSelection(.enabled).lineSpacing(4)
                HStack(spacing: 4) {
                    Text(message.date, style: .time)
                    if message.outgoing {
                        Image(systemName: message.failed ? "exclamationmark.circle" : message.pending ? "clock" : "checkmark")
                    }
                }.font(.caption2).foregroundStyle(message.outgoing ? Color.white.opacity(0.7) : .secondary)
                if message.failed {
                    HStack {
                        Text("发送失败").font(.caption)
                        if message.canRetry && message.isText {
                            Button(retrying ? "重试中…" : "重试", action: retry).font(.caption.bold()).buttonStyle(.plain)
                                .disabled(retrying).accessibilityLabel("重试发送消息")
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(message.outgoing ? .white : .primary)
            .background(message.outgoing ? Palette.accent : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: 500, alignment: message.outgoing ? .trailing : .leading)
            .contextMenu {
                Button("复制文字", systemImage: "doc.on.doc") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                    #else
                    UIPasteboard.general.string = message.text
                    #endif
                }
                if message.failed && message.canRetry && message.isText {
                    Button("重试发送", systemImage: "arrow.clockwise", action: retry).disabled(retrying)
                }
            }
            if !message.outgoing { Spacer(minLength: 48) }
        }
    }
}
