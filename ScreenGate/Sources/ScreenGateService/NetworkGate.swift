import Foundation
import SystemConfiguration
import Shared

final class NetworkGate {
    // Operate on stable service UUIDs. Never enable services that were already disabled.
    private func serviceID(_ service: SCNetworkService) throws -> String {
        guard let id = SCNetworkServiceGetServiceID(service) else {
            throw GateError("Cannot identify a network service. Network settings were not changed.")
        }
        return id as String
    }
    private func preferences() throws -> SCPreferences {
        guard let prefs = SCPreferencesCreate(nil, "ScreenGate" as CFString, nil) else {
            throw GateError("Cannot open macOS network settings.")
        }
        return prefs
    }
    func reconcile(block: Bool, state: inout StoredState) throws -> Bool {
        let prefs = try preferences()
        guard SCPreferencesLock(prefs, false) else { throw GateError("Network settings are busy. Retrying shortly.") }
        defer { SCPreferencesUnlock(prefs) }
        guard let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            throw GateError("Cannot enumerate network services.")
        }
        var changed = false
        if block {
            let enabled = services.filter { SCNetworkServiceGetEnabled($0) }
            let ids = try enabled.map { try serviceID($0) }
            for id in ids where !state.restoreServiceIDs.contains(id) { state.restoreServiceIDs.append(id) }
            if !ids.isEmpty { try state.save() } // journal first, including before a process crash
            for service in enabled {
                guard SCNetworkServiceSetEnabled(service, false) else { throw GateError("Cannot disable a network service.") }
                changed = true
            }
        } else {
            for service in services {
                guard state.restoreServiceIDs.contains(try serviceID(service)) else { continue }
                guard SCNetworkServiceSetEnabled(service, true) else { throw GateError("Cannot restore a network service.") }
                changed = true
            }
        }
        if changed {
            guard SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else {
                throw GateError("macOS could not apply network changes. Restoration will retry automatically.")
            }
        } else if block && !state.restoreServiceIDs.isEmpty {
            // A prior commit may have succeeded while ApplyChanges failed. Reapply on retries.
            guard SCPreferencesApplyChanges(prefs) else { throw GateError("Cannot apply network restriction.") }
        }
        if !block && !state.restoreServiceIDs.isEmpty {
            state.restoreServiceIDs.removeAll()
            try state.save()
        }
        return block && !services.isEmpty && services.allSatisfy { !SCNetworkServiceGetEnabled($0) }
    }
}
