import Foundation

private actor Probe {
    var version: String?
    var waitingForParameters = false
    var closed = false
    func apply(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if object["@extra"] as? String == "smoke-version" { version = object["value"] as? String }
        let state = (object["authorization_state"] as? [String: Any])?["@type"] as? String
        if state == "authorizationStateWaitTdlibParameters" { waitingForParameters = true }
        if state == "authorizationStateClosed" { closed = true }
    }
    func ready() -> Bool { version != nil && waitingForParameters }
}

@main
enum TDLibSmoke {
    static func main() async throws {
        let probe = Probe()
        let client = try TDLibClient()
        client.start { data in await probe.apply(data) }
        client.send(["@type": "getOption", "name": "version", "@extra": "smoke-version"])
        for _ in 0..<100 {
            if await probe.ready() { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let ready = await probe.ready()
        client.close()
        for _ in 0..<100 {
            if await probe.closed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard ready, await probe.closed else {
            throw NSError(domain: "Smoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "TDLib did not initialize and close correctly."])
        }
        print("TDLib \(await probe.version ?? "unknown"): dynamic loading, JSON request/response, authorization state and clean shutdown passed. No account credentials used.")
    }
}
