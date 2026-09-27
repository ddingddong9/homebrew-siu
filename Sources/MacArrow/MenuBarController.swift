import AppKit
import Network

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let overlay: BallOverlayController
    private let port: UInt16
    private let transport: MatchTransport
    private let match: MatchCoordinator
    private var player: PlayerWindowController?
    private var preview: ArenaPreviewController?
    private var layoutEditor: LayoutEditorWindowController?
    private var connectionTimer: Timer?
    private enum RoomMode: Equatable { case host, guest }
    private var roomMode: RoomMode?
    private var roomEndpoint: NWEndpoint?
    private var roomPeerID: UUID?
    private var roomBrowserWindow: RoomBrowserWindowController?
    private var joinApprovalInProgress = false
    private let createRoomItem = NSMenuItem(title: "방 만들기…", action: #selector(createRoom), keyEquivalent: "")
    private let joinRoomItem = NSMenuItem(title: "방 참가…", action: #selector(joinRoom), keyEquivalent: "")
    private let leaveRoomItem = NSMenuItem(title: "방 나가기", action: #selector(leaveRoom), keyEquivalent: "")
    private let playerMenuItem = NSMenuItem(title: "연습용 선수 생성", action: #selector(togglePlayer), keyEquivalent: "")
    private let connectionItem = NSMenuItem(title: "연결: 확인 안 됨", action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: "1대1 경기 시작…", action: #selector(startMatch), keyEquivalent: "")
    private let endItem = NSMenuItem(title: "경기 종료", action: #selector(endMatch), keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "경기장 미리보기 (AI 연습)", action: #selector(showPreview), keyEquivalent: "")

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
            self.previewItem.isEnabled = !running
            self.playerMenuItem.isEnabled = !running
            self.createRoomItem.isEnabled = !running
            self.joinRoomItem.isEnabled = !running
            self.leaveRoomItem.isEnabled = !running && self.roomMode != nil
            if running {
                self.player?.hide()
                self.playerMenuItem.title = "연습용 선수 생성"
                self.preview?.stop()
            }
            self.connectionItem.title = running ? "연결: 경기 중" : "연결: 경기 종료"
            self.connectionTimer?.invalidate()
            self.connectionTimer = running ? Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPeers(showProgress: false) { _ in } }
            } : nil
        }
        match.onConnectionIssue = { [weak self] message in
            self?.connectionItem.title = "연결 문제: \(message)"
        }
        transport.onPeerPing = { [weak self] endpoint, peerID in
            guard let self, self.roomMode == .host, !self.match.isRunning,
                  peerID != GameIdentity.localID,
                  self.roomPeerID == peerID else { return }
            self.roomEndpoint = endpoint
            self.match.setRoomPeer(endpoint)
            self.connectionItem.title = "방: 친구 연결 확인됨"
        }
        transport.onJoinRequest = { [weak self] request, reply in
            guard let self, self.roomMode == .host, !self.match.isRunning,
                  self.roomPeerID == nil, !self.joinApprovalInProgress else {
                reply(false)
                return
            }
            self.joinApprovalInProgress = true
            let alert = NSAlert()
            alert.messageText = "방 참가 요청"
            alert.informativeText = "\(request.playerName)에서 이 방에 참가하려고 합니다. 허용할까요?"
            alert.addButton(withTitle: "참가 허용")
            alert.addButton(withTitle: "거절")
            NSApplication.shared.activate(ignoringOtherApps: true)
            let accepted = alert.runModal() == .alertFirstButtonReturn
            self.joinApprovalInProgress = false
            if accepted {
                self.roomPeerID = request.playerID
                self.connectionItem.title = "방: 참가 승인됨 · 연결 확인 중…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    guard let self, self.roomMode == .host, !self.match.isRunning,
                          self.roomPeerID == request.playerID, self.roomEndpoint == nil else { return }
                    self.roomPeerID = nil
                    self.connectionItem.title = "방: 친구 참가 대기 중"
                }
            }
            reply(accepted)
        }
        match.approveInvite = { _ in
            let alert = NSAlert()
            alert.messageText = "SIU 경기 초대"
            alert.informativeText = "상대 Mac에서 경기를 시작하려고 합니다. 참가할까요?"
            alert.addButton(withTitle: "참가")
            alert.addButton(withTitle: "거절")
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            return true
        }
        statusItem.button?.title = "⚽️"
        let menu = NSMenu()
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        let checkItem = NSMenuItem(title: "연결 확인", action: #selector(checkConnection), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        createRoomItem.target = self
        joinRoomItem.target = self
        leaveRoomItem.target = self
        leaveRoomItem.isEnabled = false
        menu.addItem(createRoomItem)
        menu.addItem(joinRoomItem)
        menu.addItem(leaveRoomItem)
        menu.addItem(.separator())
        playerMenuItem.target = self
        menu.addItem(playerMenuItem)
        startItem.target = self
        menu.addItem(startItem)
        endItem.target = self
        endItem.isEnabled = false
        menu.addItem(endItem)
        previewItem.target = self
        menu.addItem(previewItem)
        menu.addItem(NSMenuItem(title: "상대 연결·화면 배치…", action: #selector(openLayout), keyEquivalent: ","))
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
            player = controller
            controller.show()
            playerMenuItem.title = "선수 숨기기"
        } else if let visible = player?.toggle() {
            playerMenuItem.title = visible ? "연습용 선수 숨기기" : "연습용 선수 생성"
        }
    }

    @objc private func checkConnection() {
        checkPeers { _ in }
    }

    @objc private func createRoom() {
        guard !match.isRunning else { return }
        let alert = NSAlert()
        alert.messageText = "방 만들기"
        alert.informativeText = "같은 와이파이의 친구에게 표시할 방 이름을 입력하세요."
        let field = NSTextField(string: "SIU 방")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 25)
        alert.accessoryView = field
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let proposed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = proposed.isEmpty ? "SIU 방" : String(proposed.prefix(25))
        roomBrowserWindow?.close()
        roomBrowserWindow = nil
        let key = RoomSecretStore.freshKey()
        transport.useRoomKey(key)
        roomMode = .host
        leaveRoomItem.isEnabled = true
        roomEndpoint = nil
        roomPeerID = nil
        match.setRoomPeer(nil)
        transport.advertiseRoom(named: name)
        connectionItem.title = "방: \(name) · 친구 참가 대기 중"
    }

    @objc private func joinRoom() {
        guard !match.isRunning else { return }
        if let roomBrowserWindow {
            roomBrowserWindow.showWindow(nil)
            roomBrowserWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        transport.advertiseRoom(named: nil)
        if let savedKey = RoomSecretStore.load() { transport.useRoomKey(savedKey) }
        roomMode = nil
        roomEndpoint = nil
        roomPeerID = nil
        match.setRoomPeer(nil)
        leaveRoomItem.isEnabled = false
        connectionItem.title = "방: 같은 와이파이에서 찾는 중…"
        let controller = RoomBrowserWindowController()
        roomBrowserWindow = controller
        controller.onJoin = { [weak self, weak controller] room in
            guard let self, let controller, self.roomBrowserWindow === controller else { return }
            let playerName = String((Host.current().localizedName ?? "친구 Mac").prefix(40))
            self.transport.requestJoin(endpoint: room.endpoint, playerName: playerName) { [weak self, weak controller] key, hostID in
                guard let self, let controller, self.roomBrowserWindow === controller else { return }
                guard let key, let hostID, hostID != GameIdentity.localID else {
                    controller.setStatus("참가가 거절되었거나 응답이 없습니다. 다시 선택하세요.", allowSelection: true)
                    return
                }
                self.transport.useRoomKey(key)
                self.transport.ping(endpoint: room.endpoint) { [weak self, weak controller] peerID in
                    guard let self, let controller, self.roomBrowserWindow === controller else { return }
                    guard peerID == hostID else {
                        if let savedKey = RoomSecretStore.load() { self.transport.useRoomKey(savedKey) }
                        controller.setStatus("방 연결 확인에 실패했습니다. 다시 시도하세요.", allowSelection: true)
                        return
                    }
                    self.roomMode = .guest
                    self.leaveRoomItem.isEnabled = true
                    self.roomEndpoint = room.endpoint
                    self.roomPeerID = hostID
                    self.match.setRoomPeer(room.endpoint)
                    self.connectionItem.title = "방: 친구 연결 확인됨"
                    controller.close()
                }
            }
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller, self.roomBrowserWindow === controller else { return }
            self.roomBrowserWindow = nil
        }
        controller.show()
    }

    @objc private func leaveRoom() {
        guard !match.isRunning else { return }
        roomBrowserWindow?.close()
        roomBrowserWindow = nil
        transport.advertiseRoom(named: nil)
        if let savedKey = RoomSecretStore.load() { transport.useRoomKey(savedKey) }
        roomMode = nil
        roomEndpoint = nil
        roomPeerID = nil
        match.setRoomPeer(nil)
        leaveRoomItem.isEnabled = false
        connectionItem.title = "연결: 확인 안 됨"
    }

    @objc private func showPreview() {
        if preview == nil { preview = ArenaPreviewController() }
        player?.hide()
        playerMenuItem.title = "연습용 선수 생성"
        preview?.show()
    }

    private func checkPeers(showProgress: Bool = true, completion: @escaping (Bool) -> Void) {
        if roomMode != nil {
            guard let roomEndpoint else {
                connectionItem.title = "방: 친구 참가 대기 중"
                completion(false)
                return
            }
            if showProgress { connectionItem.title = "방: 연결 확인 중…" }
            transport.ping(endpoint: roomEndpoint) { [weak self] peerID in
                guard let self else { completion(false); return }
                let connected = peerID != nil && peerID == self.roomPeerID
                self.connectionItem.title = !connected ? "방: 친구 연결 끊김"
                    : (self.match.isRunning ? "방: 경기 중" : "방: 친구 연결 확인됨")
                completion(connected)
            }
            return
        }
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
            guard self.match.start(duration: minutes) else {
                self.connectionItem.title = "경기 시작 실패: 상대 1명만 배치하세요"
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
