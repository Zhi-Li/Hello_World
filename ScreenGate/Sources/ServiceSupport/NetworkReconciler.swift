public struct NetworkServiceSnapshot {
    public var id: String
    public var enabled: Bool
    public init(id: String, enabled: Bool) { self.id = id; self.enabled = enabled }
}

// The production adapter uses a locked SCPreferences session. Tests use an
// in-memory session so they never change the build runner's network settings.
public protocol NetworkPreferencesSession {
    func services() throws -> [NetworkServiceSnapshot]
    func setEnabled(_ enabled: Bool, for id: String) throws
    func commit() throws
    func apply() throws
}

public final class NetworkReconciler {
    public private(set) var hasPendingApply: Bool
    private var lastTarget: Bool?

    public init(recoveringJournal: Bool = false) { hasPendingApply = recoveringJournal }

    public func reconcile(block: Bool, session: NetworkPreferencesSession,
                          restoreIDs: inout [String], persist: ([String]) throws -> Void) throws -> Bool {
        // Restoring a journal needs one successful apply even if a prior process
        // already committed enabled flags. Clearing the journal must come last.
        if !block && !restoreIDs.isEmpty && lastTarget != false { hasPendingApply = true }
        lastTarget = block
        var services = try session.services()
        var changed = false
        if block {
            let enabled = services.filter(\.enabled)
            if !enabled.isEmpty {
                for service in enabled where !restoreIDs.contains(service.id) { restoreIDs.append(service.id) }
                // Also retry this save after a failed journal write, before any disable.
                try persist(restoreIDs)
                for index in services.indices where services[index].enabled {
                    try session.setEnabled(false, for: services[index].id)
                    services[index].enabled = false; changed = true
                }
            }
        } else {
            for index in services.indices where restoreIDs.contains(services[index].id) && !services[index].enabled {
                try session.setEnabled(true, for: services[index].id)
                services[index].enabled = true; changed = true
            }
        }
        if changed {
            hasPendingApply = true
            try session.commit()
        }
        if hasPendingApply {
            try session.apply()
            hasPendingApply = false
        }
        if !block && !restoreIDs.isEmpty {
            try persist([])
            restoreIDs.removeAll()
        }
        return block && !services.isEmpty && services.allSatisfy { !$0.enabled }
    }
}
