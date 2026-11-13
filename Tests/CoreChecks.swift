import Foundation

private final class FakeTelegram: TelegramTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var receiver: (@Sendable (Data) async -> Void)?
    private var sent: [[String: Any]] = []
    func start(_ onEvent: @escaping @Sendable (Data) async -> Void) { lock.withLock { receiver = onEvent } }
    func send(_ object: [String: Any]) { lock.withLock { sent.append(object) } }
    func close() { send(["@type": "close"]) }
    func last(_ type: String) -> [String: Any] { lock.withLock { sent.last { $0["@type"] as? String == type }! } }
    func count(_ type: String) -> Int { lock.withLock { sent.filter { $0["@type"] as? String == type }.count } }
    func emit(_ object: [String: Any]) async throws {
        let callback = lock.withLock { receiver }
        await callback?(try JSONSerialization.data(withJSONObject: object))
    }
}

@main
enum CoreChecks {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/checks/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 42, count: 32).base64EncodedString()
        let url = directory.appendingPathComponent("drafts.enc")
        let vault = try DraftVault(fileURL: url, databaseKey: key)
        try vault.save([2: "明天见 🌿", 3: ""])
        let saved = try vault.load()
        precondition(saved == [2: "明天见 🌿"])
        let encrypted = try Data(contentsOf: url)
        precondition(encrypted.range(of: Data("明天见".utf8)) == nil, "Draft text must not be stored in plaintext")
        let wrongKey = try DraftVault(fileURL: url, databaseKey: Data(repeating: 1, count: 32).base64EncodedString())
        do { _ = try wrongKey.load(); fatalError("Wrong keys must be rejected") } catch { }
        var corrupt = encrypted; corrupt[corrupt.count - 1] ^= 1
        try corrupt.write(to: url)
        do { _ = try vault.load(); fatalError("Tampered drafts must be rejected") } catch { }
        try encrypted.write(to: url)

        let telegram = FakeTelegram()
        let store = AppStore(makeClient: { telegram }, encryptionKey: { key }, draftURL: url)
        store.connect(apiID: "12345", apiHash: String(repeating: "a", count: 32))
        precondition(store.draft(for: 2) == "明天见 🌿")
        try await telegram.emit(["@type": "updateAuthorizationState", "authorization_state": ["@type": "authorizationStateReady"]])
        let load = telegram.last("loadChats")
        try await telegram.emit(["@type": "error", "code": 404, "message": "Not Found", "@extra": load["@extra"]!])
        precondition(store.error == nil, "Exhausted chat lists must not report a login failure")
        try await telegram.emit(["@type": "updateUser", "user": ["id": 101, "first_name": "小林", "last_name": ""]])
        try await telegram.emit(["@type": "updateNewChat", "chat": ["id": 2, "title": "林间小组", "type": ["@type": "chatTypeBasicGroup"], "positions": [["list": ["@type": "chatListMain"], "order": "900000000000000001"]]]])
        precondition(store.sortedChats.first?.order == 900000000000000001 && store.selectedChat == nil)
        store.selectedChatID = 2; store.select(2, previous: nil)
        let request = telegram.last("getChatHistory")
        let raw: [String: Any] = ["id": 100, "chat_id": 2, "date": 1700000000, "is_outgoing": false,
                                 "sender_id": ["@type": "messageSenderUser", "user_id": 101],
                                 "content": ["@type": "messageText", "text": ["text": "周末见"]]]
        try await telegram.emit(["@type": "messages", "@extra": request["@extra"]!, "messages": [raw, raw]])
        precondition(store.messages[2]?.count == 1, "History must deduplicate message IDs")
        let first = store.messages[2]!.first!
        precondition(store.senderName(for: first) == "小林" && store.selectedChat?.isGroup == true)
        store.markVisible(first)
        precondition(telegram.count("viewMessages") == 0, "Inactive windows must not mark messages read")
        store.setSceneActive(true); store.markVisible(first)
        precondition(telegram.count("viewMessages") == 1)

        var failed = raw
        failed["id"] = 201; failed["is_outgoing"] = true
        failed["sending_state"] = ["@type": "messageSendingStateFailed", "can_retry": true, "retry_after": 0]
        try await telegram.emit(["@type": "updateMessageSendFailed", "message": failed, "old_message_id": 200])
        let failure = store.messages[2]!.first { $0.id == 201 }!
        precondition(failure.failed && failure.canRetry)
        store.retry(failure); store.retry(failure)
        precondition(telegram.count("resendMessages") == 1, "Repeated clicks must not duplicate resend requests")
        let resend = telegram.last("resendMessages")
        var pending = failed; pending["id"] = 202; pending["sending_state"] = ["@type": "messageSendingStatePending"]
        try await telegram.emit(["@type": "messages", "@extra": resend["@extra"]!, "messages": [pending]])
        precondition(store.messages[2]!.contains { $0.id == 202 && $0.pending })
        precondition(!store.messages[2]!.contains { $0.id == 201 })
        failed["sending_state"] = ["@type": "messageSendingStateFailed", "can_retry": true, "required_paid_message_star_count": 100]
        precondition(Message(json: failed)?.canRetry == false, "Paid resends need a separate flow")

        store.setDraft("新草稿", chatID: 2); store.flushDrafts()
        let restored = try vault.load(); precondition(restored[2] == "新草稿")
        try await telegram.emit(["@type": "updateAuthorizationState", "authorization_state": ["@type": "authorizationStateClosed"]])
        precondition(store.drafts.isEmpty && store.users.isEmpty && store.messages.isEmpty)
        store.connect(apiID: "12345", apiHash: String(repeating: "a", count: 32))
        precondition(store.draft(for: 2) == "新草稿", "Closing a session must preserve saved drafts")
        try await telegram.emit(["@type": "updateAuthorizationState", "authorization_state": ["@type": "authorizationStateLoggingOut"]])
        let cleared = try vault.load(); precondition(cleared.isEmpty, "Logout must clear account drafts")
        try await telegram.emit(["@type": "updateAuthorizationState", "authorization_state": ["@type": "authorizationStateClosed"]])

        store.startDemo(); store.setDraft("演示草稿", chatID: 1); store.selectedChatID = 2
        precondition(store.draft(for: 1) == "演示草稿")
        let demoFailure = store.messages[2]!.first { $0.failed }!
        store.retry(demoFailure)
        precondition(store.messages[2]!.allSatisfy { !$0.failed })
        let untouched = try vault.load(); precondition(untouched.isEmpty, "Demo drafts must not reach the account vault")
        store.leaveDemo(); precondition(store.drafts.isEmpty)
        print("Core checks passed: encrypted drafts, integrity protection, session restoration, logout cleanup, sender names, history deduplication, foreground read state, safe retry and demo isolation.")
    }
}
