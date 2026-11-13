import Foundation
import Darwin

/// One receiver for one process. JSON is copied before the next receive call.
protocol TelegramTransport: AnyObject, Sendable {
    func start(_ onEvent: @escaping @Sendable (Data) async -> Void)
    func send(_ object: [String: Any])
    func close()
}

final class TDLibClient: TelegramTransport, @unchecked Sendable {
    private typealias Create = @convention(c) () -> Int32
    private typealias Send = @convention(c) (Int32, UnsafePointer<CChar>?) -> Void
    private typealias Receive = @convention(c) (Double) -> UnsafePointer<CChar>?
    private typealias Execute = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
    private let handle: UnsafeMutableRawPointer
    private let clientID: Int32
    private let sendFunction: Send
    private let receiveFunction: Receive
    private let queue = DispatchQueue(label: "app.vibegram.tdlib.receive", qos: .userInitiated)
    private var started = false

    init() throws {
        var candidates = [String]()
        if let frameworks = Bundle.main.privateFrameworksPath {
            candidates += [frameworks + "/TDLib.framework/TDLib", frameworks + "/libtdjson.dylib"]
        }
        #if os(macOS)
        // Development only; sandboxed releases must bundle the signed framework.
        candidates += [Bundle.main.bundlePath + "/Contents/Frameworks/tdjson.framework/tdjson"]
        if let local = ProcessInfo.processInfo.environment["VIBEGRAM_TDLIB_PATH"] { candidates.insert(local, at: 0) }
        #endif
        var loaded: UnsafeMutableRawPointer?
        for candidate in candidates {
            if let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) { loaded = handle; break }
        }
        guard let library = loaded else {
            throw NSError(domain: "TDLib", code: 1, userInfo: [NSLocalizedDescriptionKey: "尚未安装 TDLib。可以先体验演示模式；真实登录的接入步骤见项目 README。"])
        }
        guard let create = dlsym(library, "td_create_client_id"), let send = dlsym(library, "td_send"),
              let receive = dlsym(library, "td_receive"), let execute = dlsym(library, "td_execute") else {
            dlclose(library)
            throw NSError(domain: "TDLib", code: 2, userInfo: [NSLocalizedDescriptionKey: "TDLib 缺少 JSON 接口，请使用包含 td_create_client_id / td_send / td_receive 的构建。"])
        }
        handle = library
        sendFunction = unsafeBitCast(send, to: Send.self)
        receiveFunction = unsafeBitCast(receive, to: Receive.self)
        // TDLib's default debug logs include request contents, potentially credentials.
        // Disable verbose logging before creating any client or sending any request.
        let executeFunction = unsafeBitCast(execute, to: Execute.self)
        "{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":0}".withCString { _ = executeFunction($0) }
        clientID = unsafeBitCast(create, to: Create.self)()
    }

    func start(_ onEvent: @escaping @Sendable (Data) async -> Void) {
        guard !started else { return }
        started = true
        queue.async { [self] in
            while true {
                guard let pointer = receiveFunction(0.5) else { continue }
                let data = Data(String(cString: pointer).utf8)
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (object["@client_id"] as? Int32) == clientID else { continue }
                // Wait for main-actor application before receiving the next event.
                let applied = DispatchSemaphore(value: 0)
                Task { await onEvent(data); applied.signal() }
                applied.wait()
                let state = object["authorization_state"] as? [String: Any]
                if state?["@type"] as? String == "authorizationStateClosed" { break }
            }
            // Keep the dynamic library loaded for process lifetime: TDLib owns threads.
        }
        send(["@type": "getAuthorizationState"])
    }

    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return }
        json.withCString { sendFunction(clientID, $0) }
    }

    func close() { send(["@type": "close"]) }
}
