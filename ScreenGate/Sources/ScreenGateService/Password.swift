import Foundation
import MacBridge
import Shared

struct PasswordRecord: Codable {
    var salt: Data
    var hash: Data
    static func create(_ password: String) throws -> PasswordRecord {
        guard password.count >= 8, password.utf8.count <= 1024 else {
            throw GateError("Use a password of at least 8 characters and at most 1,024 UTF-8 bytes.")
        }
        let salt = try randomBytes(32)
        return PasswordRecord(salt: salt, hash: try derive(password, salt: salt))
    }
    func matches(_ password: String) -> Bool {
        guard password.utf8.count <= 1024, let candidate = try? Self.derive(password, salt: salt), candidate.count == hash.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, hash) { difference |= a ^ b }
        return difference == 0
    }
    private static func derive(_ password: String, salt: Data) throws -> Data {
        var result = [UInt8](repeating: 0, count: 32)
        let status = password.withCString { pointer in
            salt.withUnsafeBytes { bytes in
                sg_derive(pointer, password.utf8.count, bytes.bindMemory(to: UInt8.self).baseAddress, salt.count, &result)
            }
        }
        guard status == 0 else { throw GateError("Cannot protect the password.") }
        return Data(result)
    }
}

func randomBytes(_ count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    guard sg_random(&bytes, count) == 0 else { throw GateError("Cannot generate a secure session.") }
    return Data(bytes)
}
