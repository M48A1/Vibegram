import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var messages: [Int64: [Message]] = [:]
    @Published var selectedChatID: Int64?
    @Published var isDemo = false
    @Published var isReady = false
    @Published var authState = ""
    @Published var connection = "未连接"
    @Published var error: String?
    @Published var showSettings = false
    @Published var busy = false
    @Published var loadingHistory: Set<Int64> = []
    @Published var exhaustedHistory: Set<Int64> = []
    @Published var sendingChats: Set<Int64> = []
    @Published private(set) var drafts: [Int64: String] = [:]
    @Published private(set) var users: [Int64: String] = [:]
    @Published private(set) var retryingMessages: Set<String> = []
    private var client: (any TelegramTransport)?
    private let makeClient: () throws -> any TelegramTransport
    private let encryptionKey: () throws -> String
    private let draftURL: URL?
    private var draftVault: DraftVault?
    private var draftSaveTask: Task<Void, Never>?
    private var sceneActive = false
    private var apiID = 0
    private var apiHash = ""
    private var databaseKey = ""
    private var requests: [String: ([String: Any]) -> Void] = [:]
    private var requestTimers: [String: Task<Void, Never>] = [:]
    private var expectedNotFound: Set<String> = []

    init(makeClient: @escaping () throws -> any TelegramTransport = { try TDLibClient() },
         encryptionKey: @escaping () throws -> String = Keychain.databaseKey,
         draftURL: URL? = nil) {
        self.makeClient = makeClient; self.encryptionKey = encryptionKey; self.draftURL = draftURL
    }

    func draft(for chatID: Int64) -> String { drafts[chatID] ?? "" }

    func setDraft(_ text: String, chatID: Int64) {
        if text.isEmpty { drafts.removeValue(forKey: chatID) } else { drafts[chatID] = text }
        draftSaveTask?.cancel()
        guard !isDemo else { return }
        draftSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flushDrafts()
        }
    }

    func flushDrafts() {
        draftSaveTask?.cancel(); draftSaveTask = nil
        guard !isDemo, let draftVault else { return }
        do { try draftVault.save(drafts) }
        catch { self.error = "草稿未能保存到本机，请保留输入内容后重试。" }
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if !active { flushDrafts() }
    }

    func senderName(for message: Message) -> String? {
        guard !message.outgoing else { return nil }
        switch message.sender {
        case .user(let id): return users[id] ?? "成员 \(id)"
        case .chat(let id): return chats.first { $0.id == id }?.title ?? "频道 \(id)"
        case nil: return nil
        }
    }

    var selectedChat: Chat? { chats.first { $0.id == selectedChatID } }
    var sortedChats: [Chat] { chats.filter { $0.order > 0 }.sorted { ($0.order, $0.id) > ($1.order, $1.id) } }
    var isConnected: Bool { client != nil }

    func startDemo() {
        guard client == nil else { return }
        isDemo = true; isReady = true; chats = DemoData.chats
        users = [101: "小林", 102: "阿禾"]; drafts = [:]
        messages = Dictionary(grouping: DemoData.messages, by: \.chatID)
        selectedChatID = 1; connection = "演示模式 · 不连接 Telegram"
    }

    func leaveDemo() {
        isDemo = false; isReady = false; chats = []; messages = [:]
        drafts = [:]; users = [:]; retryingMessages = []
        selectedChatID = nil; connection = "未连接"
    }

    func connect(apiID: String, apiHash: String) {
        guard client == nil else { return }
        guard let number = Int(apiID), number > 0, number <= Int(Int32.max),
              apiHash.count == 32, apiHash.allSatisfy({ $0.isHexDigit }) else {
            error = "请输入有效的 API ID 和 32 位 API Hash。"; return
        }
        do {
            let key = try encryptionKey()
            let url = try draftURL ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Vibegram/Drafts/drafts.enc")
            let vault = try DraftVault(fileURL: url, databaseKey: key)
            let savedDrafts = try vault.load()
            let transport = try makeClient()
            databaseKey = key; draftVault = vault; drafts = savedDrafts
            self.apiID = number; self.apiHash = apiHash
            client = transport; busy = true; connection = "正在连接…"
            transport.start { [weak self] data in
                await self?.receive(data)
            }
        } catch { self.error = error.localizedDescription }
    }

    func authenticate(_ value: String) {
        guard !busy else { return }
        let value = authState == "authorizationStateWaitPassword" ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let request: [String: Any]
        switch authState {
        case "authorizationStateWaitPhoneNumber": request = ["@type": "setAuthenticationPhoneNumber", "phone_number": value, "settings": NSNull()]
        case "authorizationStateWaitCode": request = ["@type": "checkAuthenticationCode", "code": value]
        case "authorizationStateWaitPassword": request = ["@type": "checkAuthenticationPassword", "password": value]
        case "authorizationStateWaitEmailAddress": request = ["@type": "setAuthenticationEmailAddress", "email_address": value]
        case "authorizationStateWaitEmailCode": request = ["@type": "checkAuthenticationEmailCode", "code": ["@type": "emailAddressAuthenticationCode", "code": value]]
        default: return
        }
        busy = true
        send(request) { [weak self] _ in self?.busy = false }
    }

    func loadHistory(chatID: Int64, older: Bool = false) {
        guard !isDemo, !loadingHistory.contains(chatID), !exhaustedHistory.contains(chatID) || !older else { return }
        loadingHistory.insert(chatID)
        let from = older ? (messages[chatID]?.first?.id ?? 0) : 0
        send(["@type": "getChatHistory", "chat_id": chatID, "from_message_id": from, "offset": 0, "limit": 50, "only_local": false]) { [weak self] response in
            guard let self else { return }
            self.loadingHistory.remove(chatID)
            guard let list = response["messages"] as? [[String: Any]] else { return }
            let incoming = list.compactMap(Message.init(json:))
            if incoming.isEmpty { self.exhaustedHistory.insert(chatID) }
            self.merge(incoming, chatID: chatID)
        }
    }

    func select(_ id: Int64?, previous: Int64?) {
        guard !isDemo else { return }
        if let previous, previous != id { send(["@type": "closeChat", "chat_id": previous]) }
        // Selection is assigned by SwiftUI; openChat is idempotent for current selection.
        guard let id else { return }
        send(["@type": "openChat", "chat_id": id])
        loadHistory(chatID: id)
    }

    func markVisible(_ message: Message) {
        guard !isDemo, sceneActive, selectedChatID == message.chatID, !message.outgoing else { return }
        send(["@type": "viewMessages", "chat_id": message.chatID, "message_ids": [message.id], "source": ["@type": "messageSourceChatHistory"], "force_read": true])
    }

    func sendText(_ text: String, chatID: Int64, completion: @escaping (Bool) -> Void) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { completion(false); return }
        guard text.utf16.count <= 4096 else { error = "消息过长，请分成几条发送。"; completion(false); return }
        if isDemo {
            merge([Message(id: Int64(Date.now.timeIntervalSince1970 * 1_000_000), chatID: chatID, text: text, outgoing: true)], chatID: chatID)
            if let index = chats.firstIndex(where: { $0.id == chatID }) { chats[index].preview = text; chats[index].date = .now }
            completion(true); return
        }
        guard isReady, client != nil, !sendingChats.contains(chatID) else { completion(false); return }
        sendingChats.insert(chatID)
        send(["@type": "sendMessage", "chat_id": chatID,
              "input_message_content": ["@type": "inputMessageText", "text": ["@type": "formattedText", "text": text, "entities": []], "clear_draft": true]]) { [weak self] response in
            self?.sendingChats.remove(chatID)
            if let message = Message(json: response) { self?.merge([message], chatID: chatID); completion(true) }
            else { completion(false) }
        }
    }

    func retry(_ message: Message) {
        guard message.failed, message.outgoing, message.canRetry, message.isText,
              !retryingMessages.contains(message.retryKey) else { return }
        guard message.retryAvailableAt <= .now else { error = "Telegram 要求稍后再重试，请稍等。"; return }
        if isDemo {
            var sent = message; sent.failed = false; sent.pending = false; sent.canRetry = false
            merge([sent], chatID: message.chatID)
            return
        }
        guard isReady, client != nil else { return }
        retryingMessages.insert(message.retryKey)
        send(["@type": "resendMessages", "chat_id": message.chatID, "message_ids": [message.id], "quote": NSNull(), "paid_message_star_count": 0]) { [weak self] response in
            guard let self else { return }
            self.retryingMessages.remove(message.retryKey)
            guard let raw = response["messages"] as? [[String: Any]] else { return }
            let replacements = raw.compactMap(Message.init(json:))
            guard !replacements.isEmpty else { return }
            self.messages[message.chatID]?.removeAll { $0.id == message.id }
            self.merge(replacements, chatID: message.chatID)
        }
    }

    func logout() {
        guard !busy else { return }
        busy = true
        send(["@type": "logOut"]) { [weak self] response in
            if response["@type"] as? String == "error" { self?.busy = false }
        }
    }

    func close() { flushDrafts(); client?.close() }

    private func send(_ object: [String: Any], ignoreNotFound: Bool = false, completion: (([String: Any]) -> Void)? = nil) {
        guard let client else { return }
        let id = UUID().uuidString
        var object = object; object["@extra"] = id
        if ignoreNotFound { expectedNotFound.insert(id) }
        if let completion {
            requests[id] = completion
            requestTimers[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, let callback = self.requests.removeValue(forKey: id) else { return }
                self.requestTimers[id] = nil
                self.error = "请求超时，请检查网络后重试。"
                callback(["@type": "error", "code": -1])
            }
        }
        client.send(object)
    }

    private func merge(_ incoming: [Message], chatID: Int64) {
        var keyed = Dictionary(uniqueKeysWithValues: (messages[chatID] ?? []).map { ($0.id, $0) })
        for message in incoming { keyed[message.id] = message }
        messages[chatID] = keyed.values.sorted { $0.id < $1.id }
    }

    private func updatePositions(chatID: Int64, positions: [[String: Any]]) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        let main = positions.first { ($0["list"] as? [String: Any])?["@type"] as? String == "chatListMain" }
        chats[index].order = Int64(main?["order"] as? String ?? "") ?? (main?["order"] as? NSNumber)?.int64Value ?? 0
    }

    private func receive(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["@type"] as? String else { return }
        let responseID = object["@extra"] as? String
        let ignored404 = responseID.map { expectedNotFound.remove($0) != nil } ?? false
        if type == "error", !(ignored404 && object["code"] as? Int == 404) {
            // Avoid showing raw server strings that may contain submitted credentials.
            if let message = TelegramErrorText.message(code: object["code"] as? Int ?? 0, serverMessage: object["message"] as? String ?? "") { error = message }
        }
        if let id = object["@extra"] as? String {
            requestTimers.removeValue(forKey: id)?.cancel()
            requests.removeValue(forKey: id)?(object)
        }
        switch type {
        case "updateAuthorizationState":
            let state = object["authorization_state"] as? [String: Any] ?? [:]
            authState = state["@type"] as? String ?? ""; busy = false
            switch authState {
            case "authorizationStateWaitTdlibParameters": configure()
            case "authorizationStateReady":
                isReady = true; apiHash = ""
                send(["@type": "loadChats", "chat_list": ["@type": "chatListMain"], "limit": 200], ignoreNotFound: true)
            case "authorizationStateLoggingOut":
                drafts = [:]; flushDrafts(); busy = true
            case "authorizationStateClosing": busy = true
            case "authorizationStateClosed":
                client = nil; isReady = false; busy = false; chats = []; messages = [:]; selectedChatID = nil
                apiHash = ""; connection = "已断开"; sendingChats = []
                flushDrafts(); drafts = [:]; users = [:]; retryingMessages = []; draftVault = nil
                loadingHistory = []; exhaustedHistory = []
                expectedNotFound = []
                for timer in requestTimers.values { timer.cancel() }; requestTimers = [:]; requests = [:]
            default: break
            }
        case "updateConnectionState":
            let state = (object["state"] as? [String: Any])?["@type"] as? String
            connection = state == "connectionStateReady" ? "已连接" : state == "connectionStateUpdating" ? "正在同步…" : "正在连接…"
        case "updateNewChat":
            guard let raw = object["chat"] as? [String: Any], let id = (raw["id"] as? NSNumber)?.int64Value else { return }
            let last = (raw["last_message"] as? [String: Any]).flatMap(Message.init(json:))
            let chatType = raw["type"] as? [String: Any]
            let isChannel = chatType?["is_channel"] as? Bool ?? false
            let kind = chatType?["@type"] as? String
            let chat = Chat(id: id, title: raw["title"] as? String ?? "对话", preview: last?.text ?? "", unread: raw["unread_count"] as? Int ?? 0, date: last?.date ?? .distantPast, isChannel: isChannel, isGroup: kind == "chatTypeBasicGroup" || (kind == "chatTypeSupergroup" && !isChannel))
            if let index = chats.firstIndex(where: { $0.id == id }) { chats[index] = chat } else { chats.append(chat) }
            updatePositions(chatID: id, positions: raw["positions"] as? [[String: Any]] ?? [])
        case "updateChatPosition":
            guard let id = (object["chat_id"] as? NSNumber)?.int64Value, let position = object["position"] as? [String: Any],
                  (position["list"] as? [String: Any])?["@type"] as? String == "chatListMain" else { return }
            updatePositions(chatID: id, positions: [position])
        case "updateChatLastMessage":
            guard let id = (object["chat_id"] as? NSNumber)?.int64Value, let index = chats.firstIndex(where: { $0.id == id }) else { return }
            let message = (object["last_message"] as? [String: Any]).flatMap(Message.init(json:))
            chats[index].preview = message?.text ?? ""; chats[index].date = message?.date ?? .distantPast
            updatePositions(chatID: id, positions: object["positions"] as? [[String: Any]] ?? [])
        case "updateChatTitle":
            if let id = (object["chat_id"] as? NSNumber)?.int64Value, let index = chats.firstIndex(where: { $0.id == id }) { chats[index].title = object["title"] as? String ?? chats[index].title }
        case "updateChatReadInbox":
            if let id = (object["chat_id"] as? NSNumber)?.int64Value, let index = chats.firstIndex(where: { $0.id == id }) { chats[index].unread = object["unread_count"] as? Int ?? 0 }
        case "updateUser":
            if let user = object["user"] as? [String: Any], let id = (user["id"] as? NSNumber)?.int64Value {
                let name = [user["first_name"] as? String, user["last_name"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                users[id] = name.isEmpty ? "已注销账号" : name
            }
        case "updateNewMessage", "updateMessageSendSucceeded", "updateMessageSendFailed":
            if var message = (object["message"] as? [String: Any]).flatMap(Message.init(json:)) {
                if let old = (object["old_message_id"] as? NSNumber)?.int64Value { messages[message.chatID]?.removeAll { $0.id == old } }
                if type == "updateMessageSendFailed" { message.failed = true }
                merge([message], chatID: message.chatID)
            }
        case "updateMessageContent":
            if let chatID = (object["chat_id"] as? NSNumber)?.int64Value, let id = (object["message_id"] as? NSNumber)?.int64Value,
               let index = messages[chatID]?.firstIndex(where: { $0.id == id }), let content = object["new_content"] as? [String: Any] { messages[chatID]?[index].text = Message.summary(content) }
        case "updateDeleteMessages":
            if let id = (object["chat_id"] as? NSNumber)?.int64Value, let ids = object["message_ids"] as? [Int64] { messages[id]?.removeAll { ids.contains($0.id) } }
        default: break
        }
    }

    private func configure() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Vibegram/Telegram", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var excluded = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            send(["@type": "setTdlibParameters", "use_test_dc": false,
                  "database_directory": root.path, "files_directory": root.appendingPathComponent("files").path,
                  "database_encryption_key": databaseKey, "use_file_database": true,
                  "use_chat_info_database": true, "use_message_database": true, "use_secret_chats": false,
                  "api_id": apiID, "api_hash": apiHash, "system_language_code": "zh-Hans",
                  "device_model": "Apple", "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
                  "application_version": "0.1.0"])
        } catch { self.error = error.localizedDescription; close() }
    }
}
