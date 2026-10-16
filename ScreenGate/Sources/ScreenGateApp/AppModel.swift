import SwiftUI
import AppKit
import Shared

@MainActor final class AppModel: ObservableObject {
    static var instance: AppModel?
    @Published var status: GateStatus?
    @Published var draft = GateSettings()
    @Published var token: String?
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var showingQuit = false
    @Published var showingPassword = false
    @Published var history: ScreenTimeMonth?
    @Published var historyLoading = false
    @Published var historyError: String?
    @Published var menuBarTooltip = "ScreenGate\nToday's screen time: Loading…"
    var quitAuthorized = false
    private var lastInteraction = Date()
    private var polling = false
    private var generation = 0
    private let transport = DispatchQueue(label: "com.screengate.client", qos: .userInitiated)
    private var timer: Timer?

    init() {
        Self.instance = self
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }
    func refreshMenuBarSummary() { poll() }
    var unlocked: Bool { token != nil }
    func interacted() { lastInteraction = Date() }
    func unlock(_ password: String) {
        send(GateRequest("login", password: password)) { response in
            self.token = response.token; self.draft = response.status?.settings ?? GateSettings()
            self.lastInteraction = Date()
        }
    }
    func lock() {
        generation += 1
        if let token { transport.async { _ = try? GateClient.call(GateRequest("logout", token: token)) } }
        token = nil; status = nil; draft = GateSettings(); error = nil; notice = nil
        history = nil; historyLoading = false; historyError = nil
    }
    func action(_ command: String) {
        guard let token else { return }
        interacted()
        send(GateRequest(command, token: token)) { response in
            if command == "save" { self.notice = "Schedule and allowance saved." }
            if command == "reset" { self.notice = "Today's usage reset." }
            if let settings = response.status?.settings { self.draft = settings }
        }
    }
    func save() {
        do { try draft.validate() } catch { self.error = error.localizedDescription; return }
        guard let token else { return }; interacted()
        send(GateRequest("save", token: token, settings: draft)) { _ in self.notice = "Schedule and allowance saved." }
    }
    func extendToday(minutes: Int) {
        guard let token, let day = status?.day else { return }; interacted()
        send(GateRequest("extend", token: token, extraMinutes: minutes, day: day)) { _ in
            self.notice = "Added \(minutes) minutes for today. The extra time expires at midnight."
        }
    }
    func loadHistory(month: String) {
        guard let token, !historyLoading else { return }
        interacted(); historyLoading = true; historyError = nil
        if history?.month != month { history = nil }
        let expectedGeneration = generation
        transport.async {
            let result = Result { try GateClient.call(GateRequest("history", token: token, month: month)) }
            DispatchQueue.main.async {
                guard self.generation == expectedGeneration, self.token == token else { return }
                self.historyLoading = false
                switch result {
                case .success(let response):
                    if response.ok, let history = response.history {
                        self.history = history; self.acceptStatus(response.status)
                    } else if response.unauthorized == true { self.lock() }
                    else { self.historyError = response.error ?? "History could not be loaded." }
                case .failure(let error): self.historyError = error.localizedDescription
                }
            }
        }
    }
    private func acceptStatus(_ value: GateStatus?) {
        status = value
        if let value {
            menuBarTooltip = TodayScreenTime(day: value.day, screenSeconds: value.screenSeconds,
                breakdown: value.breakdown).tooltip()
        }
        guard let value, let total = value.screenSeconds, var month = history,
              value.day.hasPrefix(month.month + "-") else { return }
        if let index = month.days.firstIndex(where: { $0.day == value.day }) {
            month.days[index].totalSeconds = total
            month.days[index].breakdown = value.breakdown
        } else {
            month.days.append(ScreenTimeDay(day: value.day, totalSeconds: total, breakdown: value.breakdown))
            month.days.sort { $0.day < $1.day }
        }
        if let started = value.recordingStartedAt { month.recordingStartedAt = started }
        history = month
    }
    func changePassword(current: String, new: String) {
        guard let token else { return }; interacted()
        send(GateRequest("password", token: token, password: current, newPassword: new)) { _ in
            self.showingPassword = false; self.notice = "Owner password updated."
        }
    }
    func requestQuit() {
        showingQuit = true
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
    func stopAndQuit(_ password: String) {
        busy = true; error = nil
        transport.async {
            let result: Result<GateResponse, Error> = Result {
                let login = try GateClient.call(GateRequest("login", password: password))
                guard login.ok, let token = login.token else { throw GateError(login.error ?? "Unable to unlock.") }
                let response = try GateClient.call(GateRequest("stop", token: token, password: password))
                guard response.ok else { throw GateError(response.error ?? "Unable to restore internet.") }
                return response
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success: self.quitAuthorized = true; NSApp.terminate(nil)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    private func send(_ request: GateRequest, completion: @escaping (GateResponse) -> Void = { _ in }) {
        guard !busy else { return }; busy = true; error = nil; notice = nil
        let expectedGeneration = generation
        transport.async {
            let result = Result { try GateClient.call(request) }
            DispatchQueue.main.async {
                self.busy = false
                guard self.generation == expectedGeneration else { return }
                switch result {
                case .success(let response):
                    if response.ok { self.acceptStatus(response.status); completion(response) }
                    else { if response.unauthorized == true { self.lock() }; self.error = response.error }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    private func poll() {
        guard !busy, !polling else { return }
        if token != nil && Date().timeIntervalSince(lastInteraction) >= 300 { lock() }
        let ownerToken = token
        polling = true
        transport.async {
            let request = ownerToken.map { GateRequest("status", token: $0) } ?? GateRequest("today")
            let result = Result { try GateClient.call(request) }
            DispatchQueue.main.async {
                self.polling = false
                // Ignore responses from an owner session that has since been locked.
                guard self.token == ownerToken else { return }
                switch result {
                case .success(let response):
                    if response.ok, ownerToken != nil { self.acceptStatus(response.status) }
                    else if response.ok, let today = response.today { self.menuBarTooltip = today.tooltip() }
                    else {
                        self.menuBarTooltip = TodayScreenTime.unavailableTooltip
                        if ownerToken != nil {
                            if response.unauthorized == true { self.lock() }
                            else { self.error = response.error }
                        }
                    }
                case .failure(let error):
                    self.menuBarTooltip = TodayScreenTime.unavailableTooltip
                    if ownerToken != nil { self.error = error.localizedDescription }
                }
            }
        }
    }
}
