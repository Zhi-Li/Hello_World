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
    var quitAuthorized = false
    private var lastInteraction = Date()
    private var polling = false
    private var generation = 0
    private let transport = DispatchQueue(label: "com.screengate.client", qos: .userInitiated)
    private var timer: Timer?

    init() {
        Self.instance = self
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
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
                    if response.ok { self.status = response.status; completion(response) }
                    else { if response.unauthorized == true { self.lock() }; self.error = response.error }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    private func poll() {
        guard let token, !busy, !polling else { return }
        if Date().timeIntervalSince(lastInteraction) >= 300 { lock(); return }
        polling = true
        transport.async {
            let result = Result { try GateClient.call(GateRequest("status", token: token)) }
            DispatchQueue.main.async {
                self.polling = false
                // Ignore responses from an owner session that has since been locked.
                guard self.token == token else { return }
                switch result {
                case .success(let response):
                    if response.ok { self.status = response.status }
                    else if response.unauthorized == true { self.lock() }
                    else { self.error = response.error }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}
