import AppKit
import Foundation

private let defaultPort: UInt16 = 45_678

private func usage() {
    print("""
    siu — kick a football from one Mac into another Mac's screen

    Usage:
      siu setup
      siu start [--port 45678]
      siu kick <left|right|hostname-or-ip> [--port 45678] [--y 0.0...1.0]
      siu layout
      siu check <hostname-or-ip> [--port 45678]
      siu demo [--y 0.0...1.0]
      siu self-test

    Examples:
      siu setup
      siu start
      siu kick left --y 0.18
      siu kick friends-mac.local
    """)
}

private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func parsedPort(_ arguments: [String]) -> UInt16? {
    guard let raw = value(after: "--port", in: arguments) else { return defaultPort }
    return UInt16(raw)
}

private func parsedY(_ arguments: [String]) -> Double {
    Double(value(after: "--y", in: arguments) ?? "0.18") ?? 0.18
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    usage()
    exit(0)
}

switch command {
case "kick", "shoot":
    guard arguments.count >= 2, let port = parsedPort(arguments) else {
        usage()
        exit(2)
    }
    let destination = arguments[1]
    let direction = ShootDirection(rawValue: destination)
    let target = direction.flatMap { ScreenLayoutStore.load().target(in: $0) }
    if direction != nil && target == nil {
        fputs("No configured screen is positioned to the \(destination). Run `siu setup`.\n", stderr)
        exit(2)
    }
    let host = target?.host ?? destination
    let entryEdge = direction == .right ? "left" : "right"
    let semaphore = DispatchSemaphore(value: 0)
    var sendError: Error?
    BallSender.send(to: host, port: port, normalizedY: parsedY(arguments), entryEdge: entryEdge) { error in
        sendError = error
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 5) == .timedOut {
        fputs("Timed out kicking the football.\n", stderr)
        exit(1)
    }
    if let sendError {
        fputs("Could not kick the football: \(sendError.localizedDescription)\n", stderr)
        exit(1)
    }
    let targetName = target.map { "\($0.name) (\($0.host))" } ?? host
    print("⚽️ Football kicked to \(targetName):\(port) — SIU!")

case "start", "receive":
    guard let port = parsedPort(arguments), port < UInt16.max else {
        usage()
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let overlay = MainActor.assumeIsolated { BallOverlayController() }
    do {
        let matchTransport = try MatchTransport(port: port + 1)
        let menuBar = MainActor.assumeIsolated {
            MenuBarController(overlay: overlay, port: port, transport: matchTransport)
        }
        let receiver = try BallReceiver(port: port) { message in
            DispatchQueue.main.async {
                overlay.showBall(normalizedY: message.normalizedY, entryEdge: message.entryEdge ?? "right")
            }
        }
        receiver.start()
        matchTransport.start()
        print("⚽️ SIU running. Football UDP \(port), match UDP \(port + 1). Use the ⚽️ menu bar icon.")
        withExtendedLifetime((receiver, matchTransport, menuBar)) { app.run() }
    } catch {
        fputs("Could not start receiver: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "demo":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let overlay = MainActor.assumeIsolated { BallOverlayController() }
    DispatchQueue.main.async {
        overlay.showBall(normalizedY: parsedY(arguments))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { app.terminate(nil) }
    }
    app.run()

case "setup":
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let editor = MainActor.assumeIsolated {
        LayoutEditorWindowController(layout: ScreenLayoutStore.load())
    }
    editor.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    withExtendedLifetime(editor) { app.run() }

case "layout":
    let layout = ScreenLayoutStore.load()
    for screen in layout.screens.sorted(by: { $0.x < $1.x }) {
        let marker = screen.isLocal ? "(내 Mac)" : "→ \(screen.host.isEmpty ? "호스트 미입력" : screen.host)"
        print("\(screen.name)  x=\(Int(screen.x)) y=\(Int(screen.y))  \(marker)")
    }

case "check":
    guard arguments.count >= 2, let port = parsedPort(arguments), port < UInt16.max else {
        usage()
        exit(2)
    }
    do {
        let transport = try MatchTransport(port: port + 1)
        var result: UUID?
        transport.ping(host: arguments[1]) { result = $0 }
        let deadline = Date().addingTimeInterval(3.5)
        while result == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if result != nil { print("✅ Connected to \(arguments[1]):\(port + 1)") }
        else { fputs("Could not reach SIU match service at \(arguments[1]):\(port + 1)\n", stderr); exit(1) }
    } catch {
        fputs("Connection check failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "self-test":
    let failures = SelfTest.run() + SelfTest.runNetwork() + SelfTest.runPairSimulation()
    if failures.isEmpty { print("Physics and match protocol self-test OK") }
    else { fputs("Self-test failed: \(failures.joined(separator: ", "))\n", stderr); exit(1) }

case "asset-check":
    let expected = [("move", 4), ("run", 4), ("run-front", 4), ("run-back", 4),
                    ("kick", 8), ("kick-front", 4), ("kick-side", 4),
                    ("tackle", 4), ("tackle-front", 4), ("tackle-back", 4)]
    for (name, count) in expected {
        for index in 1...count {
            let filename = String(format: "%@-%02d", name, index)
            guard let url = Bundle.module.url(forResource: filename, withExtension: "png"),
                  let image = NSImage(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)),
                  image.size.width > 0, image.size.height > 0, bitmap.hasAlpha else {
                fputs("Missing or non-transparent character frame: \(filename).png\n", stderr)
                exit(1)
            }
        }
    }
    print("44 transparent character frames OK")

case "--help", "-h", "help":
    usage()

default:
    usage()
    exit(2)
}
