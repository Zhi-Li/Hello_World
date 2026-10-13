import Foundation
import Darwin
import Shared
import MacBridge

umask(0o077)
guard geteuid() == 0 else { fputs("ScreenGateService must run as root via launchd.\n", stderr); exit(1) }

do {
    if CommandLine.arguments.contains("--initialize") {
        guard !FileManager.default.fileExists(atPath: GatePaths.state) else {
            throw GateError("ScreenGate already has an owner password. It will not be overwritten.")
        }
        guard let password = readLine(strippingNewline: true) else { throw GateError("Password is missing.") }
        try StoredState(password: PasswordRecord.create(password)).save()
        print("Owner password created."); exit(0)
    }
    if CommandLine.arguments.contains("--recover") {
        var state = try StoredState.load()
        state.stopped = true; state.paused = false; try state.save()
        _ = try NetworkGate().reconcile(block: false, state: &state)
        print("ScreenGate stopped; network services restored."); exit(0)
    }
    let service = try Service()
    let listener = sg_listener()
    guard listener >= 0 else { throw GateError("Launchd control socket is unavailable.") }
    service.tick(forceNetwork: true)

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
    timer.setEventHandler { service.tick() }; timer.resume()

    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler { service.restoreForShutdown(); exit(0) }; termination.resume()
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler { service.restoreForShutdown(); exit(0) }; interrupt.resume()

    let capacity = DispatchSemaphore(value: 16)
    DispatchQueue.global(qos: .utility).async {
        while true {
            let fd = accept(listener, nil, nil)
            if fd < 0 { if errno == EINTR { continue }; exit(1) }
            guard capacity.wait(timeout: .now()) == .success else { close(fd); continue }
            sg_socket_timeout(fd, 3)
            DispatchQueue.global(qos: .utility).async {
                defer { close(fd); capacity.signal() }
                do {
                    var uid: UInt32 = 0
                    guard sg_peer_uid(fd, &uid) == 0 else { throw GateError("Cannot identify the client.") }
                    let request = try Wire.read(GateRequest.self, from: fd)
                    var response = GateResponse(ok: false)
                    DispatchQueue.main.sync { response = service.handle(request, uid: uid) }
                    try Wire.write(response, to: fd)
                    DispatchQueue.main.async {
                        if request.command == "stop" && response.ok && service.exitRequested { exit(0) }
                    }
                } catch { try? Wire.write(GateResponse(ok: false, error: error.localizedDescription), to: fd) }
            }
        }
    }
    dispatchMain()
} catch {
    fputs("ScreenGate: \(error.localizedDescription)\n", stderr)
    exit(1)
}
