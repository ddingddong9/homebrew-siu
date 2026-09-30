import AppKit
import Foundation

private let defaultPort: UInt16 = 45_678

private func usage() {
    print("""
    siu — kick a football from one Mac into another Mac's screen

    Usage:
      siu setup
      siu pair-code
      siu pair
      siu start [--port 45678]
      siu kick <left|right|hostname-or-ip> [--port 45678] [--y 0.0...1.0]
      siu layout
      siu check <hostname-or-ip> [--port 45678]
      siu demo [--y 0.0...1.0]
      siu eleven-preview
      siu self-test

    Examples:
      siu setup
      siu pair-code
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
let launchedAsApp = Bundle.main.bundleURL.pathExtension == "app"
guard let command = arguments.first ?? (launchedAsApp ?
    (Bundle.main.object(forInfoDictionaryKey: "SIULaunchMode") as? String ?? "start") : nil) else {
    usage()
    exit(0)
}

switch command {
case "pair-code":
    do {
        let key = try RoomSecretStore.generate()
        print("페어링 코드: \(RoomSecretStore.code(for: key))")
        print("다른 Mac에서 `siu pair`를 실행한 뒤 코드를 입력하세요. 이 코드는 신뢰하는 사람에게만 공유하세요.")
    } catch {
        fputs("페어링 코드 저장 실패: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "pair":
    guard arguments.count == 1 else { usage(); exit(2) }
    print("상대 Mac에 표시된 32자리 페어링 코드: ", terminator: "")
    guard let input = readLine(), let key = RoomSecretStore.parse(input) else {
        fputs("32자리 페어링 코드를 입력하세요.\n", stderr)
        exit(2)
    }
    do {
        try RoomSecretStore.save(key)
        print("✅ 페어링 코드 저장됨. 이제 두 Mac에서 `siu start`를 실행하세요.")
    } catch {
        fputs("페어링 코드 저장 실패: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

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
    app.setActivationPolicy(launchedAsApp ? .regular : .accessory)
    if launchedAsApp {
        do { _ = try RoomSecretStore.generate() }
        catch { NSAlert(error: error).runModal(); exit(1) }
    }
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
        if launchedAsApp && Bundle.main.object(forInfoDictionaryKey: "SIUShowOneOnOnePreview") as? Bool == true {
            DispatchQueue.main.async { menuBar.showPreview() }
        } else if launchedAsApp && Bundle.main.object(forInfoDictionaryKey: "SIUShowElevenHome") as? Bool == true {
            DispatchQueue.main.async { menuBar.showElevenPreview() }
        }
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

case "eleven-preview":
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let preview = MainActor.assumeIsolated { ElevenMatchWindowController() }
    MainActor.assumeIsolated { preview.show() }
    withExtendedLifetime(preview) { app.run() }

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
    let failures = SelfTest.run() + SelfTest.runNetwork() + SelfTest.runPairSimulation() +
        MainActor.assumeIsolated { ElevenNetworkSelfTest.run() }
        + SelfTest.runWrongRoomSimulation() + SelfTest.runRoomJoinSimulation()
        + SelfTest.runBonjourRoomSimulation() + SelfTest.runRoomRejectionSimulation()
    if failures.isEmpty { print("Physics and match protocol self-test OK") }
    else { fputs("Self-test failed: \(failures.joined(separator: ", "))\n", stderr); exit(1) }

case "asset-check":
    let expected = [("move", 4), ("run", 4), ("run-front", 4), ("run-back", 4),
                    ("kick", 8), ("kick-front", 4), ("kick-side", 4),
                    ("tackle", 4), ("tackle-front", 4), ("tackle-back", 4)]
    for (name, count) in expected {
        for index in 1...count {
            let filename = String(format: "%@-%02d", name, index)
            guard let url = ResourceBundle.images.url(forResource: filename, withExtension: "png"),
                  let image = NSImage(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)),
                  image.size.width > 0, image.size.height > 0, bitmap.hasAlpha else {
                fputs("Missing or non-transparent character frame: \(filename).png\n", stderr)
                exit(1)
            }
        }
    }
    guard let blueURL = ResourceBundle.images.url(forResource: "blue-player", withExtension: "png"),
          let blueBitmap = NSBitmapImageRep(data: try Data(contentsOf: blueURL)),
          blueBitmap.hasAlpha else {
        fputs("Missing or non-transparent blue team sprite.\n", stderr)
        exit(1)
    }
    guard let atlas = ResourceBundle.images.url(forResource: "keeper-throw-atlas", withExtension: "png"),
          let bitmap = NSBitmapImageRep(data: try Data(contentsOf: atlas)), bitmap.hasAlpha,
          bitmap.pixelsWide == 1448, bitmap.pixelsHigh == 1086 else {
        fputs("Missing or invalid keeper/throw-in atlas.\n", stderr); exit(1)
    }
    print("44 transparent character frames, blue team sprite and keeper/throw-in atlas OK")

case "--help", "-h", "help":
    usage()

default:
    usage()
    exit(2)
}
