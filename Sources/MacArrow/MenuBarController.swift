import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let overlay: BallOverlayController
    private let port: UInt16
    private let transport: MatchTransport
    private let match: MatchCoordinator
    private var player: PlayerWindowController?
    private var layoutEditor: LayoutEditorWindowController?
    private var connectionTimer: Timer?
    private let playerMenuItem = NSMenuItem(title: "선수 생성", action: #selector(togglePlayer), keyEquivalent: "")
    private let connectionItem = NSMenuItem(title: "연결: 확인 안 됨", action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: "경기 시작…", action: #selector(startMatch), keyEquivalent: "")
    private let endItem = NSMenuItem(title: "경기 종료", action: #selector(endMatch), keyEquivalent: "")

    init(overlay: BallOverlayController, port: UInt16, transport: MatchTransport) {
        self.overlay = overlay
        self.port = port
        self.transport = transport
        self.match = MatchCoordinator(transport: transport)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        transport.onMessage = { [weak self] message in
            MainActor.assumeIsolated { self?.match.receive(message) }
        }
        match.onStateChanged = { [weak self] running in
            guard let self else { return }
            self.startItem.isEnabled = !running
            self.endItem.isEnabled = running
            self.connectionItem.title = running ? "연결: 경기 중" : "연결: 경기 종료"
            self.connectionTimer?.invalidate()
            self.connectionTimer = running ? Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPeers(showProgress: false) { _ in } }
            } : nil
        }
        match.onConnectionIssue = { [weak self] message in
            self?.connectionItem.title = "연결 문제: \(message)"
        }
        match.approveInvite = { [weak self] _ in
            guard let self else { return false }
            let alert = NSAlert()
            alert.messageText = "SIU 경기 초대"
            alert.informativeText = "상대 Mac에서 경기를 시작하려고 합니다. 참가할까요?"
            alert.addButton(withTitle: "참가")
            alert.addButton(withTitle: "거절")
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            if self.player == nil { self.togglePlayer() }
            return true
        }
        statusItem.button?.title = "⚽️"
        let menu = NSMenu()
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        let checkItem = NSMenuItem(title: "연결 확인", action: #selector(checkConnection), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        menu.addItem(.separator())
        playerMenuItem.target = self
        menu.addItem(playerMenuItem)
        startItem.target = self
        menu.addItem(startItem)
        endItem.target = self
        endItem.isEnabled = false
        menu.addItem(endItem)
        menu.addItem(NSMenuItem(title: "화면 배치…", action: #selector(openLayout), keyEquivalent: ","))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "모든 축구공 지우기", action: #selector(clearBalls), keyEquivalent: "k"))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "siu 종료", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu
    }

    @objc private func togglePlayer() {
        if player == nil {
            let controller = PlayerWindowController()
            controller.onKick = { [weak self] direction, y, power in
                guard let self else { return false }
                return self.kick(direction: direction, normalizedY: y, power: power)
            }
            match.attachPlayer(controller)
            player = controller
            controller.show()
            playerMenuItem.title = "선수 숨기기"
        } else if let visible = player?.toggle() {
            playerMenuItem.title = visible ? "선수 숨기기" : "선수 생성"
        }
    }

    @objc private func checkConnection() {
        checkPeers { _ in }
    }

    private func checkPeers(showProgress: Bool = true, completion: @escaping (Bool) -> Void) {
        let peers = ScreenLayoutStore.load().screens.filter { !$0.isLocal && !$0.host.isEmpty }
        guard !peers.isEmpty else {
            connectionItem.title = "연결: 상대 주소 없음"
            completion(false)
            return
        }
        if showProgress { connectionItem.title = "연결: 확인 중…" }
        let group = DispatchGroup()
        var failed: [String] = []
        for peer in peers {
            group.enter()
            transport.ping(host: peer.host) { peerID in
                if let peerID { self.match.registerPeer(peerID, host: peer.host) }
                else { failed.append(peer.name) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if failed.isEmpty {
                self.connectionItem.title = self.match.isRunning ? "연결: 경기 중 (\(peers.count)명)" : "연결: \(peers.count)명 확인됨"
            } else {
                self.connectionItem.title = "연결 실패: \(failed.joined(separator: ", "))"
            }
            completion(failed.isEmpty)
        }
    }

    @objc private func startMatch() {
        checkPeers { [weak self] connected in
            guard let self, connected else { return }
            let alert = NSAlert()
            alert.messageText = "경기 시간 설정"
            alert.informativeText = "경기 시간을 분 단위로 입력하세요 (1–90분)."
            alert.addButton(withTitle: "시작")
            alert.addButton(withTitle: "취소")
            let field = NSTextField(string: "5")
            field.frame = NSRect(x: 0, y: 0, width: 220, height: 25)
            alert.accessoryView = field
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard let minutes = Int(field.stringValue), (1...90).contains(minutes) else {
                self.connectionItem.title = "경기 시간은 1–90분이어야 합니다"
                return
            }
            if self.player == nil { self.togglePlayer() }
            guard self.match.start(duration: minutes) else {
                self.connectionItem.title = "경기 시작 실패: 화면 배치를 확인하세요"
                return
            }
            self.connectionItem.title = "연결: 경기 중"
        }
    }

    @objc private func endMatch() {
        match.end()
        connectionItem.title = "연결: 경기 종료"
    }

    @objc private func openLayout() {
        if let layoutEditor {
            layoutEditor.showWindow(nil)
            layoutEditor.window?.orderFrontRegardless()
            return
        }
        let editor = LayoutEditorWindowController(layout: ScreenLayoutStore.load(), terminateOnClose: false)
        editor.onClose = { [weak self] in
            self?.player?.refreshLayout()
            self?.layoutEditor = nil
        }
        layoutEditor = editor
        editor.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func clearBalls() {
        overlay.clearAll()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func kick(direction: ShootDirection, normalizedY: Double, power: Double) -> Bool {
        guard let target = ScreenLayoutStore.load().target(in: direction) else {
            statusItem.button?.title = "⚠️"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.statusItem.button?.title = "⚽️" }
            return false
        }
        let edge = direction == .left ? "right" : "left"
        BallSender.send(to: target.host, port: port, normalizedY: normalizedY, entryEdge: edge) { [weak self] error in
            DispatchQueue.main.async {
                self?.statusItem.button?.title = error == nil ? "💨" : "⚠️"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.statusItem.button?.title = "⚽️" }
            }
        }
        _ = power
        return true
    }
}
