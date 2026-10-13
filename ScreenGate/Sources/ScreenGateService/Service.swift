import Foundation
import Darwin
import Shared
import Policy
import MacBridge

final class Service {
    var state: StoredState
    private let network = NetworkGate()
    private var lastDate = Date()
    private var lastUptime = ProcessInfo.processInfo.systemUptime
    private var lastActive = false
    private var active = false
    private var blocked = false
    private var networkError: String?
    private var lastNetworkCheck = Date.distantPast
    private var lastDesired: Bool?
    private var sessions: [String: (uid: UInt32, expires: Date)] = [:]
    private var failures: [UInt32: (count: Int, until: Date)] = [:]
    var exitRequested = false

    init() throws { state = try StoredState.load() }

    func tick(forceNetwork: Bool = false) {
        let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = uptime - lastUptime
        active = sg_screen_active() == 1
        let wallDelta = now.timeIntervalSince(lastDate)
        if elapsed > 0 && elapsed <= 2.5 && abs(wallDelta - elapsed) < 2 && active && lastActive {
            // Split short samples at schedule and midnight boundaries, including DST transitions.
            let steps = max(1, Int(ceil(elapsed / 0.25)))
            for i in 0..<steps {
                let sample = lastDate.addingTimeInterval(wallDelta * (Double(i) + 0.5) / Double(steps))
                let day = dayKey(sample)
                state.usage[day] = sg_accumulate(state.usage[day] ?? 0, elapsed / Double(steps),
                    state.settings.mode(at: sample) == .afterSchool ? 1 : 0,
                    1, state.paused ? 1 : 0, state.stopped ? 1 : 0)
            }
        }
        lastDate = now; lastUptime = uptime; lastActive = active
        // Retain dates so moving the clock backwards cannot erase that day's allowance.
        let cutoff = dayKey(Calendar.current.date(byAdding: .day, value: -45, to: now) ?? now)
        state.usage = state.usage.filter { $0.key >= cutoff }
        do {
            try state.save()
            let desired = shouldBlock(now)
            if forceNetwork || desired != lastDesired || now.timeIntervalSince(lastNetworkCheck) >= 5 {
                blocked = try network.reconcile(block: desired, state: &state)
                lastNetworkCheck = now; lastDesired = desired; networkError = nil
            }
        } catch {
            networkError = error.localizedDescription
            lastDesired = nil // ensure failures retry
        }
    }

    private func shouldBlock(_ now: Date) -> Bool {
        sg_should_block(state.usage[dayKey(now)] ?? 0, Double(state.settings.dailyLimitMinutes * 60),
            state.settings.mode(at: now) == .afterSchool ? 1 : 0,
            state.paused ? 1 : 0, state.stopped ? 1 : 0) == 1
    }

    private func status() -> GateStatus {
        let now = Date()
        return GateStatus(settings: state.settings, usedSeconds: state.usage[dayKey(now)] ?? 0,
            mode: state.settings.mode(at: now), paused: state.paused, stopped: state.stopped,
            blocked: blocked, active: active, networkError: networkError, day: dayKey(now))
    }

    private func authenticate(_ password: String, uid: UInt32) throws {
        let now = Date()
        if let attempt = failures[uid], attempt.until > now {
            throw GateError("Too many attempts. Try again in \(Int(ceil(attempt.until.timeIntervalSince(now)))) seconds.")
        }
        guard state.password.matches(password) else {
            let old = failures[uid]
            let count = ((old?.until ?? .distantPast) > now.addingTimeInterval(-300) ? old?.count ?? 0 : 0) + 1
            failures[uid] = (count, count >= 5 ? now.addingTimeInterval(60) : now)
            throw GateError("Incorrect owner password.")
        }
        failures.removeValue(forKey: uid)
    }

    func handle(_ request: GateRequest, uid: UInt32) -> GateResponse {
        do {
            sessions = sessions.filter { $0.value.expires > Date() }
            if request.command == "login" {
                try authenticate(request.password ?? "", uid: uid)
                guard sessions.count < 32 else { throw GateError("Too many open owner sessions. Try again shortly.") }
                let token = try randomBytes(32).base64EncodedString()
                sessions[token] = (uid, Date().addingTimeInterval(900))
                tick()
                return GateResponse(ok: true, token: token, status: status())
            }
            guard let token = request.token, let session = sessions[token], session.uid == uid else {
                return GateResponse(ok: false, error: "Unlock with your owner password.", unauthorized: true)
            }
            switch request.command {
            case "status": tick()
            case "save":
                guard let settings = request.settings else { throw GateError("Settings are missing.") }
                try settings.validate()
                tick(); state.settings = settings; try state.save(); tick(forceNetwork: true)
            case "pause":
                tick(); state.paused = true; try state.save(); tick(forceNetwork: true)
                guard networkError == nil else { throw GateError(networkError!) }
            case "resume":
                tick(); state.paused = false; state.stopped = false; try state.save(); tick(forceNetwork: true)
            case "reset":
                tick(); state.usage[dayKey(Date())] = 0; try state.save(); tick(forceNetwork: true)
            case "stop":
                // Require a fresh password even if an owner left the window unlocked.
                try authenticate(request.password ?? "", uid: uid)
                tick(); state.stopped = true; try state.save(); tick(forceNetwork: true)
                guard networkError == nil else { throw GateError(networkError!) }
                exitRequested = true
            case "password":
                try authenticate(request.password ?? "", uid: uid)
                state.password = try PasswordRecord.create(request.newPassword ?? "")
                try state.save(); sessions = sessions.filter { $0.key == token }
            case "logout": sessions.removeValue(forKey: token)
            default: throw GateError("Unknown command.")
            }
            return GateResponse(ok: true, status: status())
        } catch { return GateResponse(ok: false, error: error.localizedDescription) }
    }

    func restoreForShutdown() {
        do { _ = try network.reconcile(block: false, state: &state); try state.save() }
        catch { fputs("ScreenGate restoration error: \(error.localizedDescription)\n", stderr) }
    }
}
