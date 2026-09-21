import AppKit
import Foundation

private let defaultPort: UInt16 = 45_678

private func usage() {
    print("""
    mac-arrow — send an arrow between two Macs

    Usage:
      mac-arrow receive [--port 45678]
      mac-arrow shoot <hostname-or-ip> [--port 45678] [--y 0.0...1.0]
      mac-arrow demo [--y 0.0...1.0]

    Examples:
      mac-arrow receive
      mac-arrow shoot 192.168.0.23 --y 0.55
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
    let semaphore = DispatchSemaphore(value: 0)
    var sendError: Error?
    ArrowSender.send(to: arguments[1], port: port, normalizedY: parsedY(arguments)) { error in
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
    print("🏹 Arrow sent to \(arguments[1]):\(port)")

case "receive":
    guard let port = parsedPort(arguments) else {
        usage()
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let overlay = MainActor.assumeIsolated { ArrowOverlayController() }
    do {
        let receiver = try ArrowReceiver(port: port) { message in
            DispatchQueue.main.async {
                overlay.showArrow(normalizedY: message.normalizedY)
            }
        }
        receiver.start()
        print("🎯 Waiting for arrows on UDP port \(port)…")
        withExtendedLifetime(receiver) { app.run() }
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

case "--help", "-h", "help":
    usage()

default:
    usage()
    exit(2)
}
