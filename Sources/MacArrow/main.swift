import AppKit
import Foundation

private let defaultPort: UInt16 = 45_678

private func usage() {
    print("""
    mac-arrow — send an arrow between two Macs

    Usage:
      mac-arrow setup
      mac-arrow receive [--port 45678]
      mac-arrow shoot <left|right|hostname-or-ip> [--port 45678] [--y 0.0...1.0]
      mac-arrow layout
      mac-arrow demo [--y 0.0...1.0]

    Examples:
      mac-arrow setup
      mac-arrow receive
      mac-arrow shoot left --y 0.55
      mac-arrow shoot friends-mac.local
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
    Double(value(after: "--y", in: arguments) ?? "0.5") ?? 0.5
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    usage()
    exit(0)
}

switch command {
case "shoot":
    guard arguments.count >= 2, let port = parsedPort(arguments) else {
        usage()
        exit(2)
    }
    let destination = arguments[1]
    let direction = ShootDirection(rawValue: destination)
    let target = direction.flatMap { ScreenLayoutStore.load().target(in: $0) }
    if direction != nil && target == nil {
        fputs("No configured screen is positioned to the \(destination). Run `mac-arrow setup`.\n", stderr)
        exit(2)
    }
    let host = target?.host ?? destination
    let entryEdge = direction == .right ? "left" : "right"
    let semaphore = DispatchSemaphore(value: 0)
    var sendError: Error?
    ArrowSender.send(to: host, port: port, normalizedY: parsedY(arguments), entryEdge: entryEdge) { error in
        sendError = error
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 5) == .timedOut {
        fputs("Timed out sending arrow.\n", stderr)
        exit(1)
    }
    if let sendError {
        fputs("Could not send arrow: \(sendError.localizedDescription)\n", stderr)
        exit(1)
    }
    let targetName = target.map { "\($0.name) (\($0.host))" } ?? host
    print("🏹 Arrow sent to \(targetName):\(port)")

case "receive":
    guard let port = parsedPort(arguments) else {
        usage()
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let overlay = MainActor.assumeIsolated { ArrowOverlayController() }
    let menuBar = MainActor.assumeIsolated { MenuBarController(overlay: overlay, port: port) }
    do {
        let receiver = try ArrowReceiver(port: port) { message in
            DispatchQueue.main.async {
                overlay.showArrow(normalizedY: message.normalizedY, entryEdge: message.entryEdge ?? "right")
            }
        }
        receiver.start()
        print("🎯 Waiting for arrows on UDP port \(port). Use the 🏹 menu bar icon to create an archer.")
        withExtendedLifetime((receiver, menuBar)) { app.run() }
    } catch {
        fputs("Could not start receiver: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "demo":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let overlay = MainActor.assumeIsolated { ArrowOverlayController() }
    DispatchQueue.main.async {
        overlay.showArrow(normalizedY: parsedY(arguments))
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

case "--help", "-h", "help":
    usage()

default:
    usage()
    exit(2)
}
