import Foundation

@main
enum ModelChecks {
    static func main() {
        let id: Int64 = 9_000_000_000_001
        let raw: [String: Any] = ["id": NSNumber(value: id), "chat_id": NSNumber(value: -1001234567890),
            "date": 1700000000, "is_outgoing": true,
            "content": ["@type": "messageText", "text": ["text": "你好 🌿"]],
            "sending_state": ["@type": "messageSendingStatePending"]]
        let message = Message(json: raw)!
        precondition(message.id == id && message.chatID == -1001234567890, "Telegram identifiers must preserve 64-bit precision")
        precondition(message.text == "你好 🌿" && message.outgoing && message.pending)
        precondition(message.date.timeIntervalSince1970 == 1700000000)
        precondition(Message(json: [:]) == nil, "Malformed messages must be ignored")
        precondition(Message.summary(["@type": "messagePhoto", "caption": ["text": "山间"]]) == "[图片] 山间")
        precondition(Message.summary(["@type": "messageFuture"]) == "[暂未支持的消息]")
        precondition(Set(DemoData.messages.map(\.id)).count == DemoData.messages.count)
        precondition(TelegramErrorText.message(code: 406, serverMessage: "private") == nil)
        precondition(TelegramErrorText.message(code: 429, serverMessage: "Too Many Requests: retry after 60") == "请求过于频繁，请等待 60 秒后再试。")
        precondition(TelegramErrorText.message(code: 400, serverMessage: "unknown secret")?.contains("secret") == false)
        print("Model checks passed: 64-bit IDs, Unicode, delivery state, date, malformed input, media fallback, demo identity and safe error text.")
    }
}
