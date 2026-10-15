import Foundation
import Darwin
import Shared

struct StoredState: Codable {
    var version = 1
    var password: PasswordRecord
    var settings = GateSettings()
    var usage: [String: Double] = [:]
    var paused = false
    var stopped = false
    // UUIDs of network services we changed, written BEFORE disabling them.
    var restoreServiceIDs: [String] = []
    // Optional on disk so version 1 state files migrate without losing owner credentials.
    var accounting: ScreenTimeLedger?
    var ledger: ScreenTimeLedger {
        get { accounting ?? ScreenTimeLedger(legacyUsage: usage) }
        set { accounting = newValue }
    }

    static func load() throws -> StoredState {
        var state = try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: GatePaths.state)))
        guard state.version == 1, state.password.salt.count == 32, state.password.hash.count == 32,
              state.usage.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw GateError("Invalid ScreenGate state.") }
        try state.settings.validate()
        try state.ledger.validate()
        state.accounting = state.ledger
        return state
    }
    func save() throws {
        let url = URL(fileURLWithPath: GatePaths.state)
        // Protected directory is created by the installer; atomic rename prevents partial state.
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        guard chmod(GatePaths.state, 0o600) == 0 else { throw GateError("Cannot secure ScreenGate state.") }
        let fd = open(GatePaths.state, O_RDONLY)
        if fd >= 0 { _ = fsync(fd); close(fd) }
        let parent = open(GatePaths.directory, O_RDONLY)
        if parent >= 0 { _ = fsync(parent); close(parent) }
    }
}

func dayKey(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    ScreenDates.dayKey(date, calendar: calendar)
}
