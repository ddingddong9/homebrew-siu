import CryptoKit
import Foundation

enum RoomSecretStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/siu/room-key", isDirectory: false)

    static func load() -> Data? {
        guard let data = try? Data(contentsOf: url), data.count == 16 else { return nil }
        return data
    }

    static func code(for key: Data) -> String {
        key.map { String(format: "%02X", $0) }.joined()
    }

    static func parse(_ raw: String) -> Data? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 32, value.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        let characters = Array(value)
        for index in stride(from: 0, to: 32, by: 2) {
            guard let byte = UInt8(String(characters[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    static func generate() throws -> Data {
        if let current = load() { return current }
        let key = SymmetricKey(size: .bits128)
        let data = key.withUnsafeBytes { Data($0) }
        try save(data)
        return data
    }

    static func save(_ data: Data) throws {
        precondition(data.count == 16)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
