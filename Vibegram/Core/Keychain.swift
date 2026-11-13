import Foundation
import Security
import CryptoKit

/// Local-only drafts. The key is derived separately from the Keychain database key.
struct DraftVault {
    let fileURL: URL
    private let key: SymmetricKey

    init(fileURL: URL, databaseKey: String) throws {
        guard let data = Data(base64Encoded: databaseKey), data.count == 32 else {
            throw NSError(domain: "Drafts", code: 1, userInfo: [NSLocalizedDescriptionKey: "草稿加密密钥无效。"])
        }
        self.fileURL = fileURL
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: data), salt: Data("Vibegram.Drafts.v1".utf8), info: Data(), outputByteCount: 32)
    }

    func load() throws -> [Int64: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let encrypted = try Data(contentsOf: fileURL)
        let box = try AES.GCM.SealedBox(combined: encrypted)
        return try JSONDecoder().decode([Int64: String].self, from: AES.GCM.open(box, using: key))
    }

    func save(_ drafts: [Int64: String]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        let data = try JSONEncoder().encode(drafts.filter { !$0.value.isEmpty })
        let encrypted = try AES.GCM.seal(data, using: key).combined!
        try encrypted.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

enum Keychain {
    static func databaseKey() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vibegram.database", kSecAttrAccount as String: "primary"]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true]) { _, new in new } as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) { return key }
        guard status == errSecItemNotFound else { throw failure(status) }
        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw failure(randomStatus) }
        let key = Data(bytes).base64EncodedString()
        let addStatus = SecItemAdd(query.merging([
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw failure(addStatus) }
        return key
    }

    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "无法访问安全存储（\(status)）。"])
    }
}
