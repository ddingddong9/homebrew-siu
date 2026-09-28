import Foundation
import Network

enum ElevenNetworkSelfTest {
    @MainActor static func run() -> [String] {
        var failures: [String] = []
        func check(_ value: Bool, _ name: String) { if !value { failures.append("eleven LAN: " + name) } }
        func pump(until condition: () -> Bool, seconds: Double = 2) {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition() && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
        let host = ElevenSession(), guest = ElevenSession()
        defer { host.stop(); guest.stop() }
        host.approve = { _ in true }
        do { try host.host(name: "SIU automated loopback test") }
        catch { return ["eleven LAN: listener creation failed: \(error.localizedDescription)"] }
        pump(until: { host.listeningPort != nil })
        guard let port = host.listeningPort, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return ["eleven LAN: listening port unavailable"]
        }
        guest.join(LocalRoom(name: "loopback", endpoint: .hostPort(host: "127.0.0.1", port: endpointPort)))
        pump(until: { host.connected && guest.connected })
        check(host.connected && guest.connected, "version handshake (host: \(host.status), guest: \(guest.status))")
        var received: ElevenSnapshot?
        var commands: [ElevenCommand] = []
        guest.onSnapshot = { received = $0 }
        host.onCommand = { command, _ in commands.append(command) }
        var e = ElevenMatchEngine()
        e.step(input: ElevenInput(), dt: 1.5)
        host.sendSnapshot(e.snapshot)
        guest.sendInput(ElevenInput(horizontal: -1, vertical: 1, sprint: true))
        guest.sendCommand(.shot); guest.sendCommand(.pause)
        pump(until: { received != nil && commands.count == 2 && host.remoteInput.horizontal == -1 })
        check(received?.players.count == 22 && received?.tick == e.simulationTicks, "full authoritative snapshot")
        check(host.remoteInput.horizontal == -1 && host.remoteInput.sprint, "remote held input")
        check(commands == [.shot, .pause], "ordered discrete actions")
        host.checkTimeout(now: ProcessInfo.processInfo.systemUptime + 0.5)
        check(host.remoteInput.horizontal == 0, "stale input neutralized")
        var disconnected = false
        host.onDisconnect = { disconnected = true }
        guest.stop()
        pump(until: { disconnected })
        check(disconnected && !host.connected, "disconnect notification")
        return failures
    }
}
