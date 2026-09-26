import AppKit

@MainActor
final class MatchCoordinator {
    private struct RemotePlayer {
        var x: Double
        var y: Double
        var seenAt: TimeInterval
    }
    var onStateChanged: ((Bool) -> Void)?
    var onConnectionIssue: ((String) -> Void)?
    var approveInvite: ((UUID) -> Bool)?
    private let transport: MatchTransport
    private let hud = MatchHUDController()
    private weak var player: PlayerWindowController?
    private var timer: Timer?
    private var matchID: UUID?
    private var duration: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var ball: MatchBall?
    private var scores: [UUID: Int] = [:]
    private var lastTouchID: UUID?
    private var peerIDsByHost: [String: UUID] = [:]
    private var remotePlayers: [UUID: RemotePlayer] = [:]
    private var lastPlayerSentAt: TimeInterval = 0
    private var lastSyncSentAt: TimeInterval = 0
    private var initiatorID: UUID?
    private var goalNoticeUntil: TimeInterval = 0
    private var seenMessageIDs = Set<UUID>()
    private var ownGoal: FieldEdge = .right
    var isRunning: Bool { matchID != nil }
    private var myScore: Int { scores[GameIdentity.localID, default: 0] }
    private var theirScore: Int { scores.filter { $0.key != GameIdentity.localID }.values.reduce(0, +) }

    init(transport: MatchTransport) { self.transport = transport }

    func registerPeer(_ id: UUID, host: String) {
        peerIDsByHost[host] = id
    }

    func attachPlayer(_ player: PlayerWindowController) {
        self.player = player
        player.onMatchKick = { [weak self] foot, direction in
            self?.kick(from: foot, direction: direction) ?? false
        }
        player.onMatchTackle = { [weak self] foot, direction in
            self?.tackle(from: foot, direction: direction)
        }
        player.setMatchMode(isRunning)
    }

    func start(duration minutes: Int) -> Bool {
        guard !isRunning else { return false }
        ownGoal = configuredGoalEdge()
        guard targetHost() != nil else { return false }
        let id = UUID()
        let seconds = TimeInterval(min(max(minutes, 1), 90) * 60)
        begin(id: id, duration: seconds, elapsed: 0, ownsKickoff: true)
        broadcast(MatchMessage(kind: .start, matchID: id, duration: seconds))
        return true
    }

    func end() {
        guard let id = matchID else { return }
        broadcast(MatchMessage(kind: .stop, matchID: id))
        finish()
    }

    func receive(_ message: MatchMessage) {
        guard !seenMessageIDs.contains(message.id) else { return }
        seenMessageIDs.insert(message.id)
        if seenMessageIDs.count > 2048 { seenMessageIDs.removeAll(keepingCapacity: true) }
        switch message.kind {
        case .start:
            guard let id = message.matchID, let duration = message.duration,
                  duration >= 60, duration <= 5400 else { return }
            let elapsed = max(0, Date().timeIntervalSince(message.sentAt))
            guard !isRunning else {
                broadcast(MatchMessage(kind: .stop, matchID: id))
                return
            }
            guard approveInvite?(message.senderID) == true else {
                broadcast(MatchMessage(kind: .stop, matchID: id))
                return
            }
            initiatorID = message.senderID
            let peers = ScreenLayoutStore.load().screens.filter { !$0.isLocal && !$0.host.isEmpty }
            if peers.count == 1 { peerIDsByHost[peers[0].host] = message.senderID }
            begin(id: id, duration: duration, elapsed: elapsed, ownsKickoff: false)
        case .stop:
            guard message.matchID == matchID else { return }
            finish()
        case .ball:
            guard message.matchID == matchID, let y = message.y,
                  let vx = message.vx, let vy = message.vy,
                  y.isFinite, vx.isFinite, vy.isFinite,
                  abs(vx) <= 4, abs(vy) <= 4 else { return }
            ball = MatchBall(x: vx >= 0 ? 0.035 : 0.965,
                             y: min(max(y, 0.10), 0.95), vx: vx, vy: vy)
            lastTouchID = message.actorID ?? message.senderID
        case .goal:
            guard message.matchID == matchID, let scorer = message.actorID else { return }
            scores[scorer, default: 0] += 1
            goalNoticeUntil = ProcessInfo.processInfo.systemUptime + 2
            render()
        case .player:
            guard message.matchID == matchID, let x = message.x, let y = message.y,
                  (0...1).contains(x), (0...1).contains(y) else { return }
            remotePlayers[message.senderID] = RemotePlayer(x: x, y: y,
                                                             seenAt: ProcessInfo.processInfo.systemUptime)
        case .tackle:
            guard message.matchID == matchID, let remote = remotePlayers[message.senderID],
                  let foot = player?.footPosition,
                  ProcessInfo.processInfo.systemUptime - remote.seenAt < 1 else { return }
            let sharedLeft = ownGoal == .right
            guard (sharedLeft ? remote.x > 0.72 : remote.x < 0.28),
                  distanceToSharedEdge(foot) < 190,
                  abs(normalizedY(foot) - remote.y) < 0.17 else { return }
            player?.stunForTackle()
            if var current = ball, (sharedLeft ? current.x < 0.23 : current.x > 0.77),
               abs(current.y - remote.y) < 0.19 {
                MatchPhysics.tackle(&current, dx: sharedLeft ? -1 : 1, dy: 0)
                ball = current
                lastTouchID = message.senderID
            }
        case .sync:
            guard message.matchID == matchID, let incoming = message.scores else { return }
            for (key, value) in incoming where value >= 0 && value <= 999 {
                guard let id = UUID(uuidString: key) else { continue }
                scores[id] = max(scores[id, default: 0], value)
            }
            if message.senderID == initiatorID, let remaining = message.remaining,
               remaining.isFinite, remaining >= 0, remaining <= duration {
                let now = ProcessInfo.processInfo.systemUptime
                let adjusted = max(0, remaining - max(0, Date().timeIntervalSince(message.sentAt)))
                let current = max(0, duration - (now - startedAt))
                if abs(current - adjusted) > 0.8 { startedAt = now - (duration - adjusted) }
            }
            render()
        case .ping, .pong, .ack: break
        }
    }

    private func begin(id: UUID, duration: TimeInterval, elapsed: TimeInterval, ownsKickoff: Bool) {
        timer?.invalidate()
        matchID = id
        self.duration = duration
        startedAt = ProcessInfo.processInfo.systemUptime - elapsed
        lastTick = ProcessInfo.processInfo.systemUptime
        scores = [:]
        ball = ownsKickoff ? .kickoff : nil
        lastTouchID = ownsKickoff ? GameIdentity.localID : nil
        remotePlayers = [:]
        lastPlayerSentAt = 0
        lastSyncSentAt = 0
        if ownsKickoff { initiatorID = GameIdentity.localID }
        goalNoticeUntil = 0
        ownGoal = configuredGoalEdge()
        hud.show(ownGoal: ownGoal)
        player?.setMatchMode(true)
        player?.show()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        onStateChanged?(true)
        render()
    }

    private func finish() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        matchID = nil
        ball = nil
        player?.setMatchMode(false)
        onStateChanged?(false)
        hud.update(ball: nil, myScore: myScore, theirScore: theirScore, remaining: 0, status: "경기 종료")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.isRunning else { return }
            self.hud.hide()
        }
    }

    private func tick() {
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick
        lastTick = now
        if now - startedAt >= duration { end(); return }
        if now - lastPlayerSentAt >= 0.2, let foot = player?.footPosition,
           let screen = NSScreen.main ?? NSScreen.screens.first, let id = matchID {
            lastPlayerSentAt = now
            let x = Double((foot.x - screen.frame.minX) / screen.frame.width)
            let y = Double((foot.y - screen.frame.minY) / screen.frame.height)
            broadcast(MatchMessage(kind: .player, matchID: id,
                                   x: min(max(x, 0), 1), y: min(max(y, 0), 1)))
        }
        if now - lastSyncSentAt >= 2, let id = matchID {
            lastSyncSentAt = now
            let scoreboard = Dictionary(uniqueKeysWithValues: scores.map { ($0.key.uuidString, $0.value) })
            broadcast(MatchMessage(kind: .sync, matchID: id, scores: scoreboard,
                                   remaining: max(0, duration - (now - startedAt))))
        }
        if var movingBall = ball {
            switch MatchPhysics.step(&movingBall, dt: dt, ownGoal: ownGoal) {
            case .inPlay: ball = movingBall
            case .ownGoal:
                ball = nil
                let scorer = lastTouchID != GameIdentity.localID ? lastTouchID : nil
                let credited = scorer ?? targetHost().flatMap { peerIDsByHost[$0] }
                if let credited { scores[credited, default: 0] += 1 }
                goalNoticeUntil = now + 2
                if let id = matchID, let credited {
                    broadcast(MatchMessage(kind: .goal, matchID: id, actorID: credited))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
                    guard let self, self.isRunning, self.ball == nil else { return }
                    self.ball = .kickoff
                    self.lastTouchID = GameIdentity.localID
                }
            case .transferred(let y, let vx, let vy):
                if let id = matchID, let host = targetHost() {
                    ball = nil
                    let packet = MatchMessage(kind: .ball, matchID: id, y: y, vx: vx, vy: vy, actorID: lastTouchID)
                    transport.send(packet, to: host) { [weak self] error in
                        guard let self, self.matchID == id, error != nil else { return }
                        self.onConnectionIssue?("공 전달 실패: 상대 연결을 확인하세요")
                        if self.ball == nil {
                            movingBall.x = self.ownGoal == .right ? 0.04 : 0.96
                            movingBall.vx = -movingBall.vx * 0.5
                            self.ball = movingBall
                        }
                    }
                } else {
                    movingBall.x = ownGoal == .right ? 0.03 : 0.97
                    movingBall.vx *= -0.6
                    ball = movingBall
                }
            }
        }
        render()
    }

    private func render() {
        let now = ProcessInfo.processInfo.systemUptime
        let sharedLeft = ownGoal == .right
        let nearbyPlayers = remotePlayers.values
            .filter { now - $0.seenAt < 1 && (sharedLeft ? $0.x > 0.72 : $0.x < 0.28) }
            .map { CGPoint(x: sharedLeft ? 0.035 : 0.965, y: $0.y) }
        hud.update(ball: ball, myScore: myScore, theirScore: theirScore,
                   remaining: max(0, duration - (now - startedAt)),
                   status: now < goalNoticeUntil ? "골!" : "", remotePlayers: nearbyPlayers)
    }

    private func kick(from foot: CGPoint, direction: CGPoint) -> Bool {
        guard isRunning, var ball, isNear(foot, ball: ball, radius: 130) else { return false }
        MatchPhysics.kick(&ball, dx: direction.x, dy: direction.y)
        self.ball = ball
        lastTouchID = GameIdentity.localID
        return true
    }

    private func tackle(from foot: CGPoint, direction: CGPoint) {
        guard isRunning else { return }
        if var ball, isNear(foot, ball: ball, radius: 145) {
            MatchPhysics.tackle(&ball, dx: direction.x, dy: direction.y)
            self.ball = ball
            lastTouchID = GameIdentity.localID
        }
        if distanceToSharedEdge(foot) < 190, let id = matchID {
            broadcast(MatchMessage(kind: .tackle, matchID: id,
                                   y: normalizedY(foot), actorID: GameIdentity.localID))
        }
    }

    private func distanceToSharedEdge(_ point: CGPoint) -> CGFloat {
        guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame else { return .infinity }
        return ownGoal == .right ? point.x - frame.minX : frame.maxX - point.x
    }

    private func normalizedY(_ point: CGPoint) -> Double {
        guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame else { return 0 }
        return Double((point.y - frame.minY) / frame.height)
    }

    private func isNear(_ foot: CGPoint, ball: MatchBall, radius: CGFloat) -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let point = CGPoint(x: screen.frame.minX + screen.frame.width * ball.x,
                            y: screen.frame.minY + screen.frame.height * ball.y)
        return hypot(point.x - foot.x, point.y - foot.y) <= radius
    }

    private func targetHost() -> String? {
        ScreenLayoutStore.load().target(in: ownGoal == .right ? .left : .right)?.host
    }

    private func configuredGoalEdge() -> FieldEdge {
        let layout = ScreenLayoutStore.load()
        let localX = layout.screens.first(where: \.isLocal)?.x ?? 0
        let peerX = layout.screens.filter { !$0.isLocal }.map(\.x)
        return peerX.isEmpty || localX >= peerX.reduce(0, +) / Double(peerX.count) ? .right : .left
    }

    private func broadcast(_ message: MatchMessage) {
        for peer in ScreenLayoutStore.load().screens where !peer.isLocal && !peer.host.isEmpty {
            transport.send(message, to: peer.host) { [weak self] error in
                if error != nil {
                    self?.onConnectionIssue?("\(peer.name) 응답 없음")
                    if message.kind == .start { self?.end() }
                }
            }
        }
    }
}
