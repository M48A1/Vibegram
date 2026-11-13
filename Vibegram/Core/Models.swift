import Foundation

struct Chat: Identifiable, Hashable {
    let id: Int64
    var title: String
    var preview: String = ""
    var unread = 0
    var order: Int64 = 0
    var date = Date.distantPast
    var isChannel = false
    var isGroup = false
}

enum MessageSender: Hashable {
    case user(Int64)
    case chat(Int64)

    init?(json: [String: Any]) {
        if json["@type"] as? String == "messageSenderUser", let id = (json["user_id"] as? NSNumber)?.int64Value { self = .user(id) }
        else if json["@type"] as? String == "messageSenderChat", let id = (json["chat_id"] as? NSNumber)?.int64Value { self = .chat(id) }
        else { return nil }
    }
}

enum TelegramErrorText {
    static func message(code: Int, serverMessage: String) -> String? {
        guard code != 406 else { return nil }
        let messages = [
            "API_ID_INVALID": "API ID 或 API Hash 不正确，请检查应用凭证。",
            "PHONE_NUMBER_INVALID": "手机号格式不正确，请包含国家区号。",
            "PHONE_CODE_INVALID": "验证码不正确，请重新输入。",
            "PHONE_CODE_EXPIRED": "验证码已过期，请重新开始登录。",
            "PASSWORD_HASH_INVALID": "两步验证密码不正确，请重新输入。",
            "PHONE_NUMBER_BANNED": "该账号目前无法登录，请在官方 Telegram 中检查账号状态。",
            "CHAT_WRITE_FORBIDDEN": "你目前没有在这个对话中发送消息的权限。",
            "MESSAGE_TOO_LONG": "消息过长，请分成几条发送。"
        ]
        if let known = messages[serverMessage] { return known }
        for prefix in ["FLOOD_WAIT_", "Too Many Requests: retry after "] {
            if serverMessage.hasPrefix(prefix), let seconds = Int(serverMessage.dropFirst(prefix.count)), seconds > 0 {
                return "请求过于频繁，请等待 \(seconds) 秒后再试。"
            }
        }
        if code == 429 { return "请求过于频繁，请稍后重试。" }
        return "Telegram 请求失败（\(code)）。请检查输入、网络或稍后重试。"
    }
}

struct Message: Identifiable, Equatable {
    let id: Int64
    let chatID: Int64
    var text: String
    let date: Date
    let outgoing: Bool
    var pending = false
    var failed = false
    var sender: MessageSender?
    var canRetry = false
    var retryAvailableAt = Date.distantPast
    var isText = true
    var retryKey: String { "\(chatID):\(id)" }

    init(id: Int64, chatID: Int64, text: String, date: Date = .now, outgoing: Bool, pending: Bool = false, failed: Bool = false, sender: MessageSender? = nil, canRetry: Bool = false) {
        self.id = id; self.chatID = chatID; self.text = text
        self.date = date; self.outgoing = outgoing; self.pending = pending; self.failed = failed
        self.sender = sender; self.canRetry = canRetry
    }

    init?(json: [String: Any]) {
        guard let id = (json["id"] as? NSNumber)?.int64Value,
              let chatID = (json["chat_id"] as? NSNumber)?.int64Value else { return nil }
        let content = json["content"] as? [String: Any] ?? [:]
        self.init(id: id, chatID: chatID, text: Self.summary(content),
                  date: Date(timeIntervalSince1970: (json["date"] as? NSNumber)?.doubleValue ?? 0),
                  outgoing: json["is_outgoing"] as? Bool ?? false,
                  pending: (json["sending_state"] as? [String: Any])?["@type"] as? String == "messageSendingStatePending",
                  failed: (json["sending_state"] as? [String: Any])?["@type"] as? String == "messageSendingStateFailed")
        sender = (json["sender_id"] as? [String: Any]).flatMap(MessageSender.init(json:))
        isText = content["@type"] as? String == "messageText"
        if let failure = json["sending_state"] as? [String: Any], failed {
            canRetry = failure["can_retry"] as? Bool == true
                && failure["need_another_sender"] as? Bool != true
                && failure["need_another_reply_quote"] as? Bool != true
                && failure["need_drop_reply"] as? Bool != true
                && ((failure["required_paid_message_star_count"] as? NSNumber)?.int64Value ?? 0) == 0
            retryAvailableAt = Date.now.addingTimeInterval((failure["retry_after"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    static func summary(_ content: [String: Any]) -> String {
        if let text = (content["text"] as? [String: Any])?["text"] as? String { return text }
        let caption = (content["caption"] as? [String: Any])?["text"] as? String ?? ""
        let labels = ["messagePhoto": "图片", "messageVideo": "视频", "messageDocument": "文件", "messageVoiceNote": "语音", "messageSticker": "贴纸"]
        return "[\(labels[content["@type"] as? String ?? ""] ?? "暂未支持的消息")]" + (caption.isEmpty ? "" : " \(caption)")
    }
}

enum DemoData {
    static let chats = [
        Chat(id: 1, title: "收藏夹", preview: "把灵感留在这里。", order: 3, date: .now),
        Chat(id: 2, title: "林间小组", preview: "周末去山里走走？", unread: 2, order: 2, date: .now.addingTimeInterval(-900), isGroup: true),
        Chat(id: 3, title: "设计拾光", preview: "少一点打扰，多一点专注。", order: 1, date: .now.addingTimeInterval(-7200), isChannel: true)
    ]
    static let messages = [
        Message(id: 1, chatID: 1, text: "欢迎来到 Vibegram。", outgoing: false),
        Message(id: 2, chatID: 1, text: "这是演示空间。这里的消息只保存在本次运行中，不会发送到 Telegram。", outgoing: false),
        Message(id: 3, chatID: 1, text: "留一点空间，给真正重要的对话。", outgoing: true),
        Message(id: 4, chatID: 2, text: "周末去山里走走？", outgoing: false, sender: .user(101)),
        Message(id: 5, chatID: 3, text: "少一点打扰，多一点专注。", outgoing: false),
        Message(id: 6, chatID: 2, text: "好呀，周六早上出发。", outgoing: false, sender: .user(102)),
        Message(id: 7, chatID: 2, text: "这是一条模拟发送失败的消息，可以点按下方重试。", outgoing: true, failed: true, canRetry: true)
    ]
}
