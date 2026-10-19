import Foundation

// Live counters remain in memory; only changed state needs periodic persistence.
public final class UsageCheckpoint {
    public private(set) var isDirty = false
    private let interval: TimeInterval
    private var lastSaved: TimeInterval
    private var retryAfter: TimeInterval = -.infinity

    public init(interval: TimeInterval = 30, at uptime: TimeInterval) {
        self.interval = interval; lastSaved = uptime
    }
    public func markDirty() { isDirty = true }
    public func didSave(at uptime: TimeInterval) {
        isDirty = false; lastSaved = uptime; retryAfter = -.infinity
    }
    public func flush(at uptime: TimeInterval, force: Bool = false, write: () throws -> Void) throws {
        guard isDirty, force || (uptime >= retryAfter && uptime - lastSaved >= interval) else { return }
        do {
            try write()
            didSave(at: uptime)
        } catch {
            // Retain dirty data without hammering a failing disk every second.
            retryAfter = uptime + 5
            throw error
        }
    }
}
