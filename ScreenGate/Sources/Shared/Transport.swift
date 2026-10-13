import Foundation
import Darwin
import MacBridge

public enum Wire {
    public static func read<T: Decodable>(_ type: T.Type, from fd: Int32) throws -> T {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        let capacity = buffer.count
        while data.count <= 65536 {
            let n = Darwin.read(fd, &buffer, capacity)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw GateError("The background service did not respond. Please try again.") }
            data.append(contentsOf: buffer.prefix(n))
            if let newline = data.firstIndex(of: 10) {
                guard newline <= 65536 else { break }
                return try JSONDecoder().decode(type, from: data.prefix(upTo: newline))
            }
        }
        throw GateError("Request is too large.")
    }

    public static func write<T: Encodable>(_ value: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(value); data.append(10)
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, base.advanced(by: sent), raw.count - sent)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw GateError("Cannot reach the background service.") }
                sent += n
            }
        }
    }
}

public enum GateClient {
    public static func call(_ request: GateRequest) throws -> GateResponse {
        let fd = sg_connect()
        guard fd >= 0 else { throw GateError("ScreenGate is not installed or its service is unavailable. Run Install.command.") }
        defer { close(fd) }
        var peer: UInt32 = 1
        guard sg_peer_uid(fd, &peer) == 0, peer == 0 else { throw GateError("The control service is not trusted.") }
        try Wire.write(request, to: fd)
        return try Wire.read(GateResponse.self, from: fd)
    }
}
