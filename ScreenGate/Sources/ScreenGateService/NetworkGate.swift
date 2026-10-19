import Foundation
import SystemConfiguration
import Shared
import ServiceSupport

private final class SystemNetworkSession: NetworkPreferencesSession {
    private let prefs: SCPreferences
    private let networkServices: [SCNetworkService]
    private let servicesByID: [String: SCNetworkService]

    init() throws {
        guard let prefs = SCPreferencesCreate(nil, "ScreenGate" as CFString, nil) else {
            throw GateError("Cannot open macOS network settings.")
        }
        guard SCPreferencesLock(prefs, false) else { throw GateError("Network settings are busy. Retrying shortly.") }
        do {
            guard let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
                throw GateError("Cannot enumerate network services.")
            }
            var byID: [String: SCNetworkService] = [:]
            for service in services {
                guard let id = SCNetworkServiceGetServiceID(service) else {
                    throw GateError("Cannot identify a network service. Network settings were not changed.")
                }
                byID[id as String] = service
            }
            self.prefs = prefs; networkServices = services; servicesByID = byID
        } catch {
            SCPreferencesUnlock(prefs)
            throw error
        }
    }
    deinit { SCPreferencesUnlock(prefs) }
    func services() throws -> [NetworkServiceSnapshot] {
        try networkServices.map { service in
            guard let id = SCNetworkServiceGetServiceID(service) else { throw GateError("Cannot identify a network service.") }
            return NetworkServiceSnapshot(id: id as String, enabled: SCNetworkServiceGetEnabled(service))
        }
    }
    func setEnabled(_ enabled: Bool, for id: String) throws {
        guard let service = servicesByID[id], SCNetworkServiceSetEnabled(service, enabled) else {
            throw GateError(enabled ? "Cannot restore a network service." : "Cannot disable a network service.")
        }
    }
    func commit() throws {
        guard SCPreferencesCommitChanges(prefs) else { throw GateError("macOS could not save network changes. Retrying shortly.") }
    }
    func apply() throws {
        guard SCPreferencesApplyChanges(prefs) else { throw GateError("macOS could not apply network changes. Retrying shortly.") }
    }
}

final class NetworkGate {
    private var reconciler: NetworkReconciler?
    func reconcile(block: Bool, state: inout StoredState, didPersist: () -> Void = {}) throws -> Bool {
        if reconciler == nil { reconciler = NetworkReconciler(recoveringJournal: !state.restoreServiceIDs.isEmpty) }
        guard let reconciler else { return false }
        // Unrestricted mode needs no preferences session once restoration is complete.
        if !block && state.restoreServiceIDs.isEmpty && !reconciler.hasPendingApply { return false }
        let session = try SystemNetworkSession()
        var restoreIDs = state.restoreServiceIDs
        defer { state.restoreServiceIDs = restoreIDs }
        return try reconciler.reconcile(block: block, session: session, restoreIDs: &restoreIDs) { ids in
            state.restoreServiceIDs = ids
            try state.save()
            didPersist()
        }
    }
}
