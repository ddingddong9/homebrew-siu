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
      siu demo [--y 0.0...1.0]

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
    guard let port = parsedPort(arguments) else {
        usage()
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let overlay = MainActor.assumeIsolated { BallOverlayController() }
    let menuBar = MainActor.assumeIsolated { MenuBarController(overlay: overlay, port: port) }
    do {
        let receiver = try BallReceiver(port: port) { message in
            DispatchQueue.main.async {
                overlay.showBall(normalizedY: message.normalizedY, entryEdge: message.entryEdge ?? "right")
            }
        }
        receiver.start()
        print("⚽️ Waiting for footballs on UDP port \(port). Use the ⚽️ menu bar icon to create a player.")
        withExtendedLifetime((receiver, menuBar)) { app.run() }
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

case "asset-check":
    guard let url = Bundle.module.url(forResource: "siu-character", withExtension: "png"),
          NSImage(contentsOf: url) != nil else {
        fputs("Could not load character asset.\n", stderr)
        exit(1)
    }
    print("character asset OK")

case "--help", "-h", "help":
    usage()

default:
    usage()
    exit(2)
}
