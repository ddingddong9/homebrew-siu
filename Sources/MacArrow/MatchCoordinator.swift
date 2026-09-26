import AppKit

@MainActor
final class MatchCoordinator {
    var onStateChanged: ((Bool) -> Void)?
    var onConnectionIssue: ((String) -> Void)?
    var approveInvite: ((UUID) -> Bool)?

    private let transport: MatchTransport
    private let arena = ArenaWindowController()
    private var timer: Timer?
    private var matchID: UUID?
    private var isHost = false
    private var duration: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var lastPlayerSentAt: TimeInterval = 0
    private var lastBallSentAt: TimeInterval = 0
    private var lastSyncSentAt: TimeInterval = 0
    private var latestBallAt = Date.distantPast
    private var latestPlayerAt = Date.distantPast
    private var latestSyncAt = Date.distantPast
    private var ball = ArenaBall.kickoff
    private var leftScore = 0
    private var rightScore = 0
    private var remotePlayer = CGPoint(x: 0.75, y: 0.5)
    private var remoteDirection = CGPoint(x: -1, y: 0)
    private var remoteSeenAt: TimeInterval = 0
    private var goalNoticeUntil: TimeInterval = 0
    private var kickoffAt: TimeInterval = 0
    private var lastKickAt: TimeInterval = 0
    private var lastTackleAt: TimeInterval = 0
    private var seenMessageIDs = Set<UUID>()

    var isRunning: Bool { matchID != nil }

    init(transport: MatchTransport) {
        self.transport = transport
        arena.onKick = { [weak self] position, direction in self?.kick(from: position, direction: direction) }
        arena.onTackle = { [weak self] position, direction in self?.tackle(from: position, direction: direction) }
        arena.onClose = { [weak self] in
            guard let self else { return }
            if self.isRunning { self.end() }
            self.arena.hide()
        }
    }

    func registerPeer(_ id: UUID, host: String) { _ = (id, host) }

    func start(duration minutes: Int) -> Bool {
        guard !isRunning, targetHost() != nil else { return false }
        let id = UUID()
        let seconds = TimeInterval(min(max(minutes, 1), 90) * 60)
        begin(id: id, duration: seconds, elapsed: 0, host: true)
        send(MatchMessage(kind: .start, matchID: id, duration: seconds), reportFailure: true)
        return true
    }

    func end() {
        guard let id = matchID else { return }
        send(MatchMessage(kind: .stop, matchID: id))
        finish()
    }

    func receive(_ message: MatchMessage) {
        guard seenMessageIDs.insert(message.id).inserted else { return }
        if seenMessageIDs.count > 2048 { seenMessageIDs.removeAll(keepingCapacity: true) }
        switch message.kind {
        case .start:
            guard let id = message.matchID, let seconds = message.duration,
                  (60...5400).contains(seconds) else { return }
            guard !isRunning else {
                send(MatchMessage(kind: .stop, matchID: id))
                return
            }
            guard approveInvite?(message.senderID) == true else {
                send(MatchMessage(kind: .stop, matchID: id))
                return
            }
            begin(id: id, duration: seconds,
                  elapsed: max(0, Date().timeIntervalSince(message.sentAt)), host: false)
        case .stop:
            guard message.matchID == matchID else { return }
            finish()
        case .player:
            guard message.matchID == matchID, let x = message.x, let y = message.y,
                  let dx = message.vx, let dy = message.vy,
                  [x, y, dx, dy].allSatisfy(\.isFinite),
                  (0.05...0.95).contains(x), (0.08...0.92).contains(y),
                  (0.5...1.5).contains(hypot(dx, dy)),
                  message.sentAt > latestPlayerAt else { return }
            latestPlayerAt = message.sentAt
            remoteSeenAt = ProcessInfo.processInfo.systemUptime
            remotePlayer = CGPoint(x: x, y: y)
            remoteDirection = CGPoint(x: dx, y: dy)
            arena.setRemote(position: remotePlayer, direction: remoteDirection)
        case .kick:
            guard message.matchID == matchID else { return }
            if !isHost { arena.animateRemoteKick(); return }
            guard ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1,
                  let dx = message.vx, let dy = message.vy,
                  dx.isFinite, dy.isFinite, (0.5...1.5).contains(hypot(dx, dy)) else { return }
            arena.animateRemoteKick()
            applyKick(from: remotePlayer, direction: CGPoint(x: dx, y: dy))
        case .tackle:
            guard message.matchID == matchID else { return }
            arena.animateRemoteTackle()
            if isHost {
                guard ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1,
                      let dx = message.vx, let dy = message.vy,
                      dx.isFinite, dy.isFinite, (0.5...1.5).contains(hypot(dx, dy)),
                      applyTackle(from: remotePlayer, direction: CGPoint(x: dx, y: dy)) else { return }
                if hypot(remotePlayer.x - arena.localPosition.x,
                         remotePlayer.y - arena.localPosition.y) < 0.08 { arena.stun() }
            } else if hypot(arena.localPosition.x - remotePlayer.x,
                            arena.localPosition.y - remotePlayer.y) < 0.08 { arena.stun() }
        case .ball:
            guard !isHost, message.matchID == matchID,
                  let x = message.x, let y = message.y, let vx = message.vx, let vy = message.vy,
                  [x, y, vx, vy].allSatisfy(\.isFinite),
                  (0...1).contains(x), (0...1).contains(y), abs(vx) <= 2, abs(vy) <= 2,
                  message.sentAt > latestBallAt else { return }
            latestBallAt = message.sentAt
            ball = ArenaBall(x: x, y: y, vx: vx, vy: vy)
        case .sync:
            guard !isHost, message.matchID == matchID, let scores = message.scores,
                  let left = scores["left"], let right = scores["right"],
                  (0...999).contains(left), (0...999).contains(right),
                  message.sentAt > latestSyncAt else { return }
            latestSyncAt = message.sentAt
            leftScore = max(leftScore, left)
            rightScore = max(rightScore, right)
            if let remaining = message.remaining, remaining.isFinite,
               remaining >= 0, remaining <= duration {
                let corrected = max(0, remaining - max(0, Date().timeIntervalSince(message.sentAt)))
                let current = max(0, duration - (ProcessInfo.processInfo.systemUptime - startedAt))
                if abs(current - corrected) > 0.8 {
                    startedAt = ProcessInfo.processInfo.systemUptime - (duration - corrected)
                }
            }
            if message.x == 1 { goalNoticeUntil = ProcessInfo.processInfo.systemUptime + 1.5 }
        case .goal, .ping, .pong, .ack: break
        }
    }

    private func begin(id: UUID, duration: TimeInterval, elapsed: TimeInterval, host: Bool) {
        timer?.invalidate()
        matchID = id
        isHost = host
        self.duration = duration
        startedAt = ProcessInfo.processInfo.systemUptime - elapsed
        lastTick = ProcessInfo.processInfo.systemUptime
        lastPlayerSentAt = 0
        lastBallSentAt = 0
        lastSyncSentAt = 0
        latestBallAt = .distantPast
        latestPlayerAt = .distantPast
        latestSyncAt = .distantPast
        ball = .kickoff
        remotePlayer = CGPoint(x: host ? 0.75 : 0.25, y: 0.5)
        remoteDirection = CGPoint(x: host ? -1 : 1, y: 0)
        remoteSeenAt = 0
        leftScore = 0
        rightScore = 0
        goalNoticeUntil = 0
        kickoffAt = 0
        lastKickAt = 0
        lastTackleAt = 0
        arena.show(homeSide: host ? .left : .right)
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
        onStateChanged?(false)
        arena.render(ball: ball, myScore: isHost ? leftScore : rightScore,
                     theirScore: isHost ? rightScore : leftScore,
                     remaining: 0, status: "경기 종료")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.isRunning else { return }
            self.arena.hide()
        }
    }

    private func tick() {
        guard let id = matchID else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick
        lastTick = now
        if now - startedAt >= duration {
            if isHost { end() } else { finish() }
            return
        }
        arena.advance(dt: dt)
        if now - lastPlayerSentAt >= 0.10 {
            lastPlayerSentAt = now
            let position = arena.localPosition
            let direction = arena.localDirection
            send(MatchMessage(kind: .player, matchID: id, x: position.x, y: position.y,
                              vx: direction.x, vy: direction.y))
        }
        if isHost {
            if now >= kickoffAt {
                switch ArenaPhysics.step(&ball, dt: dt) {
                case .inPlay:
                    ArenaPhysics.contact(&ball, player: arena.localPosition,
                                         direction: arena.localDirection)
                    if now - remoteSeenAt < 1 {
                        ArenaPhysics.contact(&ball, player: remotePlayer,
                                             direction: remoteDirection)
                    }
                case .goalAtLeft: rightScore += 1; scored(at: now)
                case .goalAtRight: leftScore += 1; scored(at: now)
                }
            }
            if now - lastBallSentAt >= 0.10 {
                lastBallSentAt = now
                send(MatchMessage(kind: .ball, matchID: id, x: ball.x, y: ball.y,
                                  vx: ball.vx, vy: ball.vy))
            }
            if now - lastSyncSentAt >= 0.5 {
                lastSyncSentAt = now
                sendScore(goal: false)
            }
        } else {
            _ = ArenaPhysics.step(&ball, dt: dt) // Visual prediction between host snapshots.
        }
        render()
    }

    private func scored(at now: TimeInterval) {
        ball = .kickoff
        kickoffAt = now + 1.4
        goalNoticeUntil = now + 2
        sendScore(goal: true)
    }

    private func render() {
        let now = ProcessInfo.processInfo.systemUptime
        arena.render(ball: ball, myScore: isHost ? leftScore : rightScore,
                     theirScore: isHost ? rightScore : leftScore,
                     remaining: max(0, duration - (now - startedAt)),
                     status: now < goalNoticeUntil ? "GOAL!" : "")
    }

    private func kick(from position: CGPoint, direction: CGPoint) {
        guard let id = matchID else { return }
        if hypot(ball.x - position.x, ball.y - position.y) >= 0.075 {
            arena.showFeedback("공에 더 가까이 가세요!")
            return
        }
        if isHost {
            if applyKick(from: position, direction: direction) {
                send(MatchMessage(kind: .kick, matchID: id, vx: direction.x, vy: direction.y))
            }
        } else {
            send(MatchMessage(kind: .kick, matchID: id, vx: direction.x, vy: direction.y))
        }
    }

    @discardableResult
    private func applyKick(from position: CGPoint, direction: CGPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= kickoffAt, now - lastKickAt > 0.28,
              ArenaPhysics.kick(&ball, from: position, direction: direction) else { return false }
        lastKickAt = now
        return true
    }

    private func tackle(from position: CGPoint, direction: CGPoint) {
        guard let id = matchID else { return }
        if isHost {
            guard applyTackle(from: position, direction: direction) else { return }
            if ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1,
               hypot(position.x - remotePlayer.x, position.y - remotePlayer.y) < 0.08 {
                send(MatchMessage(kind: .tackle, matchID: id))
            }
        } else { send(MatchMessage(kind: .tackle, matchID: id, vx: direction.x, vy: direction.y)) }
    }

    @discardableResult
    private func applyTackle(from position: CGPoint, direction: CGPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTackleAt > 0.85 else { return false }
        lastTackleAt = now
        _ = ArenaPhysics.tackle(&ball, from: position, direction: direction)
        return true
    }

    private func sendScore(goal: Bool) {
        guard let id = matchID else { return }
        send(MatchMessage(kind: .sync, matchID: id, x: goal ? 1 : 0,
                          scores: ["left": leftScore, "right": rightScore],
                          remaining: max(0, duration - (ProcessInfo.processInfo.systemUptime - startedAt))))
    }

    private func targetHost() -> String? {
        let peers = ScreenLayoutStore.load().screens.filter { !$0.isLocal && !$0.host.isEmpty }
        return peers.count == 1 ? peers[0].host : nil
    }

    private func send(_ message: MatchMessage, reportFailure: Bool = false) {
        guard let address = targetHost() else { return }
        transport.send(message, to: address) { [weak self] error in
            guard reportFailure, error != nil else { return }
            self?.onConnectionIssue?("상대 연결 실패")
            if message.kind == .start { self?.finish() }
        }
    }
}
