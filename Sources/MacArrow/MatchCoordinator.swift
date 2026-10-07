import AppKit
import Network

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
    private var latestKickoffAt = Date.distantPast
    private var latestRemoteControlAt = Date.distantPast
    private var ball = ArenaBall.kickoff
    private var leftScore = 0
    private var rightScore = 0
    private var remotePlayer = CGPoint(x: 0.75, y: 0.5)
    private var remoteDirection = CGPoint(x: -1, y: 0)
    private var remoteSeenAt: TimeInterval = 0
    private var goalNoticeUntil: TimeInterval = 0
    private var kickoffAt: TimeInterval = 0
    private var kickoffOwner: FieldEdge? = .left
    private var pausedAt: TimeInterval?
    private var powerReleaseAt: TimeInterval = 0
    private var powerActorSide: FieldEdge?
    private var fireUntil: TimeInterval = 0
    private var lastPowerAt: TimeInterval = 0
    private var leftFallenUntil: TimeInterval = 0
    private var rightFallenUntil: TimeInterval = 0
    private var lastKickAt: TimeInterval = 0
    private var lastTackleAt: TimeInterval = 0
    private var tackleCooldown: [FieldEdge:Double] = [:]
    private var sliding: [FieldEdge:Double] = [:]
    private var slidePosition: [FieldEdge:CGPoint] = [:]
    private var lastTurnAt: TimeInterval = 0
    private var lastRainbowAt: TimeInterval = 0
    private var lastPhantomAt: TimeInterval = 0
    private var lastSpecialAt: [FieldEdge: TimeInterval] = [:]
    private var seenMessageIDs = Set<UUID>()
    private var roomPeerEndpoint: NWEndpoint?

    var isRunning: Bool { matchID != nil }

    init(transport: MatchTransport) {
        self.transport = transport
        arena.onKick = { [weak self] position, direction in self?.kick(from: position, direction: direction) }
        arena.onTackle = { [weak self] position, direction in self?.tackle(from: position, direction: direction) }
        arena.onPowerShot = { [weak self] position in self?.powerShot(from: position) }
        arena.onMarseille = { [weak self] in self?.marseille() }
        arena.onRainbow = { [weak self] in self?.rainbow() }
        arena.onPhantom = { [weak self] vertical in self?.phantom(vertical: vertical) }
        arena.onStepover = { [weak self] in self?.special(.stepover) }
        arena.onBackheel = { [weak self] in self?.special(.backheel) }
        arena.onCurveShot = { [weak self] position, direction in
            self?.kick(from: position, direction: direction, curved: true)
        }
        arena.onPauseToggle = { [weak self] in self?.togglePause() }
        arena.onResume = { [weak self] in self?.resume() }
        arena.onEnd = { [weak self] in self?.end() }
        arena.onClose = { [weak self] in
            guard let self else { return }
            if self.isRunning { self.end() }
            self.arena.hide()
        }
    }

    func registerPeer(_ id: UUID, host: String) { _ = (id, host) }

    func setRoomPeer(_ endpoint: NWEndpoint?) { roomPeerEndpoint = endpoint }

    func start(duration minutes: Int) -> Bool {
        guard !isRunning, targetEndpoint() != nil else { return false }
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
            guard let stamina = message.stamina, stamina.isFinite, (0...100).contains(stamina) else { return }
            latestPlayerAt = message.sentAt
            arena.setRemoteStamina(stamina)
            remoteSeenAt = ProcessInfo.processInfo.systemUptime
            remotePlayer = CGPoint(x: x, y: y)
            remoteDirection = CGPoint(x: dx, y: dy)
            arena.setRemote(position: remotePlayer, direction: remoteDirection)
        case .kick, .curveShot:
            guard message.matchID == matchID, pausedAt == nil else { return }
            if !isHost { arena.animateRemoteKick(); return }
            guard ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1,
                  let dx = message.vx, let dy = message.vy,
                  dx.isFinite, dy.isFinite, (0.5...1.5).contains(hypot(dx, dy)) else { return }
            arena.animateRemoteKick()
            applyKick(from: remotePlayer, direction: CGPoint(x: dx, y: dy), side: .right,
                      curved: message.kind == .curveShot)
        case .tackle:
            guard message.matchID == matchID, pausedAt == nil else { return }
            if isHost {
                guard ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1,
                      let dx = message.vx, let dy = message.vy,
                      dx.isFinite, dy.isFinite, (0.5...1.5).contains(hypot(dx, dy)),
                      applyTackle(from: remotePlayer, direction: CGPoint(x: dx, y: dy),
                                  side: .right) else { return }
                arena.animateRemoteTackle()
                send(MatchMessage(kind:.tackle,matchID:matchID,vx:dx,vy:dy,actorID:message.senderID))
            } else if message.actorID != GameIdentity.localID {
                arena.animateRemoteTackle()
            }
        case .fall:
            guard !isHost, message.matchID == matchID,
                  message.sentAt >= latestKickoffAt,
                  let victim = side(from: message.x) else { return }
            applyFall(to: victim, notifyPeer: false)
        case .kickoff:
            guard !isHost, message.matchID == matchID,
                  let conceding = side(from: message.x), message.sentAt > latestKickoffAt else { return }
            latestKickoffAt = message.sentAt
            ball = .kickoff
            latestBallAt = message.sentAt
            kickoffOwner = conceding
            kickoffAt = ProcessInfo.processInfo.systemUptime + max(0, (message.duration ?? 2)
                - Date().timeIntervalSince(message.sentAt))
            powerActorSide = nil
            fireUntil = 0
            leftFallenUntil = 0
            rightFallenUntil = 0
            remotePlayer = CGPoint(x: ArenaPhysics.startingX(conceding: conceding).left, y: 0.5)
            remoteDirection = CGPoint(x: 1, y: 0)
            arena.setFireBall(false)
            arena.resetForKickoff(conceding: conceding)
            arena.animateSpecial(.celebration, local: conceding == .left,
                                 elapsed: max(0, Date().timeIntervalSince(message.sentAt)))
        case .powerShot:
            guard message.matchID == matchID, pausedAt == nil else { return }
            if isHost {
                guard ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1 else { return }
                beginPowerShot(from: remotePlayer, side: .right, actorID: message.senderID)
            } else if message.sentAt >= latestKickoffAt, let actor = message.actorID {
                beginPowerVisual(side: actor == GameIdentity.localID ? .right : .left)
            }
        case .marseille:
            guard message.matchID == matchID, pausedAt == nil else { return }
            if isHost {
                guard message.actorID == nil,
                      ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1 else { return }
                beginMarseille(side: .right, actorID: message.senderID)
            } else if message.sentAt >= latestKickoffAt, let actor = message.actorID {
                arena.startMarseille(local: actor == GameIdentity.localID)
            }
        case .rainbow:
            guard message.matchID == matchID, pausedAt == nil else { return }
            if isHost {
                guard message.actorID == nil,
                      ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1 else { return }
                beginRainbow(side: .right, actorID: message.senderID)
            } else if message.sentAt >= latestKickoffAt, let actor = message.actorID {
                arena.animateRainbow(local: actor == GameIdentity.localID)
            }
        case .phantom:
            guard message.matchID == matchID, pausedAt == nil,
                  let vertical = message.y, abs(vertical) == 1 else { return }
            if isHost {
                guard message.actorID == nil,
                      ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1 else { return }
                beginPhantom(side: .right, actorID: message.senderID, vertical: vertical)
            } else if message.sentAt >= latestKickoffAt, let actor = message.actorID {
                arena.startPhantom(local: actor == GameIdentity.localID, vertical: vertical)
            }
        case .pause:
            guard message.matchID == matchID, message.sentAt > latestRemoteControlAt else { return }
            latestRemoteControlAt = message.sentAt
            pause(notifyPeer: false)
        case .stepover, .backheel:
            guard message.matchID == matchID, pausedAt == nil, message.sentAt >= latestKickoffAt else { return }
            let move: SpecialMove = message.kind == .stepover ? .stepover : .backheel
            if isHost {
                guard message.actorID == nil, ProcessInfo.processInfo.systemUptime - remoteSeenAt < 1 else { return }
                beginSpecial(move, side: .right, actorID: message.senderID)
            } else if let actor = message.actorID {
                arena.animateSpecial(move, local: actor == GameIdentity.localID,
                                     elapsed: max(0, Date().timeIntervalSince(message.sentAt)))
            }
        case .resume:
            guard message.matchID == matchID, message.sentAt > latestRemoteControlAt else { return }
            latestRemoteControlAt = message.sentAt
            resume(notifyPeer: false)
        case .ball:
            guard !isHost, message.matchID == matchID,
                  let x = message.x, let y = message.y, let vx = message.vx, let vy = message.vy,
                  [x, y, vx, vy].allSatisfy(\.isFinite),
                  (0...1).contains(x), (0...1).contains(y), abs(vx) <= 3, abs(vy) <= 3,
                  message.sentAt > latestBallAt else { return }
            guard let z = message.z, let vz = message.vz, let curve = message.curve,
                  z.isFinite, vz.isFinite, curve.isFinite,
                  (0...0.5).contains(z), abs(vz) <= 2, abs(curve) <= 3 else { return }
            guard let dribblePhase = message.dribblePhase, dribblePhase.isFinite,
                  (0...(2 * .pi)).contains(dribblePhase) else { return }
            latestBallAt = message.sentAt
            ball = ArenaBall(x: x, y: y, vx: vx, vy: vy,
                             carrier: side(from: message.possession), z: z, vz: vz, curve: curve)
            ball.dribblePhase = dribblePhase
            ball.curveGoal = side(from: message.curveGoal)
            ball.lastCarryPosition = ball.carrier == .right ? arena.localPosition : arena.remotePosition
        case .sync:
            guard !isHost, message.matchID == matchID, let scores = message.scores,
                  let left = scores["left"], let right = scores["right"],
                  (0...999).contains(left), (0...999).contains(right),
                  message.sentAt > latestSyncAt,
                  message.sentAt >= latestKickoffAt else { return }
            latestSyncAt = message.sentAt
            leftScore = max(leftScore, left)
            rightScore = max(rightScore, right)
            if let remaining = message.remaining, remaining.isFinite, pausedAt == nil,
               remaining >= 0, remaining <= duration {
                let corrected = max(0, remaining - max(0, Date().timeIntervalSince(message.sentAt)))
                let current = max(0, duration - (ProcessInfo.processInfo.systemUptime - startedAt))
                if abs(current - corrected) > 0.8 {
                    startedAt = ProcessInfo.processInfo.systemUptime - (duration - corrected)
                }
            }
            if message.y == 2 { kickoffOwner = nil }
            else if let side = side(from: message.y) { kickoffOwner = side }
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
        latestKickoffAt = .distantPast
        latestRemoteControlAt = .distantPast
        ball = .kickoff
        remotePlayer = CGPoint(x: host ? 0.75 : 0.46, y: 0.5)
        remoteDirection = CGPoint(x: host ? -1 : 1, y: 0)
        remoteSeenAt = 0
        leftScore = 0
        rightScore = 0
        goalNoticeUntil = 0
        kickoffAt = ProcessInfo.processInfo.systemUptime + 1.2
        kickoffOwner = .left
        pausedAt = nil
        powerReleaseAt = 0
        powerActorSide = nil
        fireUntil = 0
        lastPowerAt = 0
        leftFallenUntil = 0
        rightFallenUntil = 0
        lastKickAt = 0
        lastTackleAt = 0
        sliding = [:]; tackleCooldown = [:]; slidePosition = [:]
        lastTurnAt = 0
        lastRainbowAt = 0
        lastPhantomAt = 0
        lastSpecialAt.removeAll()
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
        pausedAt = nil
        arena.setPaused(false)
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
        if pausedAt != nil { render(); return }
        if now - startedAt >= duration {
            if isHost { end() } else { finish() }
            return
        }
        if let side = powerActorSide, now >= powerReleaseAt {
            if isHost {
                let striker = side == .left ? arena.localPosition : remotePlayer
                _ = ArenaPhysics.powerKick(&ball, from: striker,
                                           toward: side == .left ? .right : .left)
                kickoffOwner = nil
            }
            powerActorSide = nil
        }
        if now >= kickoffAt && powerActorSide == nil { arena.advance(dt: dt) }
        for side in Array(tackleCooldown.keys) { tackleCooldown[side] = max(0,(tackleCooldown[side] ?? 0)-min(dt,0.05)) }
        for side in Array(sliding.keys) {
            if isHost && now >= kickoffAt {
                resolveSlideContact(from:side == .left ? arena.localPosition : remotePlayer,
                                    direction:side == .left ? arena.localDirection : remoteDirection,side:side)
            }
            sliding[side] = max(0,(sliding[side] ?? 0)-min(dt,0.05))
            if sliding[side] == 0 { sliding[side] = nil }
        }
        arena.setFireBall(now >= powerReleaseAt && now < fireUntil)
        if now - lastPlayerSentAt >= 0.10 {
            lastPlayerSentAt = now
            let position = arena.localPosition
            let direction = arena.localDirection
            send(MatchMessage(kind: .player, matchID: id, x: position.x, y: position.y,
                              vx: direction.x, vy: direction.y, stamina:arena.stamina))
        }
        if isHost {
            if now >= kickoffAt && powerActorSide == nil {
                if let carrier = ball.carrier {
                    let position = carrier == .left ? arena.localPosition : remotePlayer
                    let direction = carrier == .left ? arena.localDirection : remoteDirection
                    ArenaPhysics.carry(&ball, beside: position, direction: direction,
                                       turnProgress: arena.marseilleProgress(side: carrier),
                                       stepoverProgress: arena.specialProgress(side: carrier, move: .stepover))
                }
                switch ArenaPhysics.step(&ball, dt: dt) {
                case .inPlay:
                    acquireOrBounce(side: .left, position: arena.localPosition,
                                    direction: arena.localDirection)
                    if now - remoteSeenAt < 1 {
                        acquireOrBounce(side: .right, position: remotePlayer,
                                        direction: remoteDirection)
                    }
                case .goalAtLeft: rightScore += 1; scored(at: now, conceding: .left)
                case .goalAtRight: leftScore += 1; scored(at: now, conceding: .right)
                }
            }
            if now - lastBallSentAt >= 0.10 {
                lastBallSentAt = now
                send(MatchMessage(kind: .ball, matchID: id, x: ball.x, y: ball.y,
                                  vx: ball.vx, vy: ball.vy, z: ball.z, vz: ball.vz,
                                  curve: ball.curve,
                                  possession: ball.carrier.map { $0 == .left ? 0 : 1 } ?? 2,
                                  dribblePhase: ball.dribblePhase, curveGoal: ball.curveGoal.map { $0 == .left ? 0 : 1 }))
            }
            if now - lastSyncSentAt >= 0.5 {
                lastSyncSentAt = now
                sendScore(goal: false)
            }
        } else if now >= kickoffAt && powerActorSide == nil {
            if let carrier = ball.carrier {
                let localSide: FieldEdge = isHost ? .left : .right
                let position = carrier == localSide ? arena.localPosition : arena.remotePosition
                let direction = carrier == localSide ? arena.localDirection : remoteDirection
                ArenaPhysics.carry(&ball, beside: position, direction: direction,
                                   turnProgress: arena.marseilleProgress(side: carrier),
                                   stepoverProgress: arena.specialProgress(side: carrier, move: .stepover))
            }
            _ = ArenaPhysics.step(&ball, dt: dt) // Visual prediction between host snapshots.
        }
        render()
    }

    private func acquireOrBounce(side: FieldEdge, position: CGPoint, direction: CGPoint) {
        guard ball.carrier == nil,
              ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side),
              ProcessInfo.processInfo.systemUptime >= (side == .left ? leftFallenUntil : rightFallenUntil) else { return }
        if ArenaPhysics.capture(&ball, by: side, player: position) {
            ArenaPhysics.carry(&ball, beside: position, direction: direction)
            if kickoffOwner != nil { kickoffOwner = nil; sendScore(goal: false) }
        } else if hypot(ball.vx, ball.vy) >= 0.7 {
            _ = ArenaPhysics.contact(&ball, player: position, direction: direction)
        }
    }

    private func scored(at now: TimeInterval, conceding side: FieldEdge) {
        ball = .kickoff
        kickoffOwner = side
        let celebrationTime = SpecialMove.celebration.duration + 0.2
        kickoffAt = now + celebrationTime
        goalNoticeUntil = kickoffAt
        fireUntil = 0
        leftFallenUntil = 0
        rightFallenUntil = 0
        arena.setFireBall(false)
        arena.resetForKickoff(conceding: side)
        arena.animateSpecial(.celebration, local: side == .right)
        if let id = matchID {
            send(MatchMessage(kind: .kickoff, matchID: id,
                              duration: celebrationTime, x: side == .left ? 0 : 1))
        }
        sendScore(goal: true)
    }

    private func render() {
        let now = ProcessInfo.processInfo.systemUptime
        let time = pausedAt ?? now
        let status: String
        if time < goalNoticeUntil { status = "GOAL!" }
        else if time < kickoffAt {
            status = kickoffOwner == (isHost ? .left : .right) ? "내 선공" : "상대 선공"
        } else { status = "" }
        arena.render(ball: ball, myScore: isHost ? leftScore : rightScore,
                     theirScore: isHost ? rightScore : leftScore,
                     remaining: max(0, duration - (time - startedAt)), status: status)
    }

    private func kick(from position: CGPoint, direction: CGPoint, curved: Bool = false) {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side), ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side) else {
            arena.showFeedback("상대 선공입니다")
            return
        }
        if hypot(ball.x - position.x, ball.y - position.y) >= 0.075 {
            arena.showFeedback("공에 더 가까이 가세요!")
            return
        }
        if isHost {
            if applyKick(from: position, direction: direction, side: .left, curved: curved) {
                send(MatchMessage(kind: curved ? .curveShot : .kick, matchID: id,
                                  vx: direction.x, vy: direction.y))
            }
        } else {
            send(MatchMessage(kind: curved ? .curveShot : .kick, matchID: id,
                              vx: direction.x, vy: direction.y))
        }
    }

    @discardableResult
    private func applyKick(from position: CGPoint, direction: CGPoint, side: FieldEdge,
                           curved: Bool = false) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard canAct(side: side), ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side),
              now - lastKickAt > 0.28,
              (curved ? ArenaPhysics.curveKick(&ball, from: position, direction: direction,
                                                toward: side == .left ? .right : .left) :
                         ArenaPhysics.kick(&ball, from: position, direction: direction,
                                           aimToward: side == .left ? .right : .left)) else { return false }
        lastKickAt = now
        if kickoffOwner != nil { kickoffOwner = nil; sendScore(goal: false) }
        return true
    }

    private func tackle(from position: CGPoint, direction: CGPoint) {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side), kickoffOwner == nil else { return }
        if isHost {
            guard applyTackle(from: position, direction: direction, side: .left) else { return }
            send(MatchMessage(kind: .tackle, matchID: id, vx: direction.x, vy: direction.y))
        } else {
            guard arena.startSlide() else { return }
            send(MatchMessage(kind: .tackle, matchID: id, vx: direction.x, vy: direction.y))
        }
    }

    @discardableResult
    private func applyTackle(from position: CGPoint, direction: CGPoint,
                             side: FieldEdge) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard canAct(side: side), kickoffOwner == nil,
              (tackleCooldown[side] ?? 0) <= 0 else { return false }
        if side == .left, !arena.startSlide() { return false }
        tackleCooldown[side] = 1.15; sliding[side] = AthleteMotion.slideDuration
        slidePosition[side] = position
        lastTackleAt = now
        resolveSlideContact(from:position,direction:direction,side:side)
        return true
    }

    private func resolveSlideContact(from position:CGPoint,direction:CGPoint,side:FieldEdge) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= (side == .left ? leftFallenUntil : rightFallenUntil) else { sliding[side] = nil; return }
        let stored = slidePosition[side] ?? position
        let previous = hypot(stored.x-position.x,stored.y-position.y) < 0.15 ? stored : position
        slidePosition[side] = position
        let nearBall = SlidingContact.closest(to:CGPoint(x:ball.x,y:ball.y),from:previous,to:position)
        let wasCarriedByOpponent = ball.carrier == (side == .left ? FieldEdge.right : .left)
        let opponent: FieldEdge = side == .left ? .right : .left
        let isOpponentTurning = arena.marseilleProgress(side: opponent) != nil ||
            arena.phantomProgress(side: opponent) != nil
        if !wasCarriedByOpponent || !isOpponentTurning {
            _ = ArenaPhysics.tackle(&ball, from: nearBall, direction: direction)
        }
        let victim: FieldEdge = side == .left ? .right : .left
        let target = victim == .left ? arena.localPosition : remotePlayer
        let nearVictim = SlidingContact.closest(to:target,from:previous,to:position)
        if !isOpponentTurning, now - remoteSeenAt < 1,
           hypot(nearVictim.x - target.x, nearVictim.y - target.y) < 0.08 {
            applyFall(to: victim, notifyPeer: true)
        }
    }

    private func applyFall(to victim: FieldEdge, notifyPeer: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if victim == .left {
            guard now >= leftFallenUntil else { return }
            leftFallenUntil = now + 1.55
        } else {
            guard now >= rightFallenUntil else { return }
            rightFallenUntil = now + 1.55
        }
        if victim == (isHost ? .left : .right) { arena.stun() }
        else { arena.stunRemote() }
        if ball.carrier == victim { ArenaPhysics.dispossess(&ball, direction: CGPoint(x: victim == .left ? 1 : -1, y: 0)) }
        if notifyPeer, let id = matchID {
            send(MatchMessage(kind: .fall, matchID: id, x: victim == .left ? 0 : 1))
        }
    }

    private func canAct(side: FieldEdge) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return pausedAt == nil && now >= kickoffAt && powerActorSide == nil &&
            (sliding[side] ?? 0) <= 0 && (side != (isHost ? .left : .right) || !arena.isSliding) &&
            arena.specialProgress(side: side) == nil &&
            arena.marseilleProgress(side: side) == nil && arena.phantomProgress(side: side) == nil &&
            now >= (side == .left ? leftFallenUntil : rightFallenUntil)
    }

    private func side(from value: Double?) -> FieldEdge? {
        if value == 0 { return .left }
        if value == 1 { return .right }
        return nil
    }

    private func special(_ move: SpecialMove) {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side), ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side) else { return }
        if move == .stepover && ball.carrier != side {
            arena.showFeedback("공을 소유해야 발재간을 할 수 있어요"); return
        }
        if move == .backheel && (ball.z >= 0.03 || hypot(ball.x-arena.localPosition.x, ball.y-arena.localPosition.y) >= 0.075) {
            arena.showFeedback("공에 가까이 가서 Q를 누르세요"); return
        }
        if isHost { beginSpecial(move, side: side, actorID: GameIdentity.localID) }
        else { send(MatchMessage(kind: move == .stepover ? .stepover : .backheel, matchID: id)) }
    }

    private func beginSpecial(_ move: SpecialMove, side: FieldEdge, actorID: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        guard isHost, let id = matchID, move != .celebration, canAct(side: side),
              ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side),
              now - (lastSpecialAt[side] ?? -.infinity) >= move.duration + 0.3 else { return }
        if move == .stepover {
            guard ball.carrier == side else { return }
        } else {
            let position = side == .left ? arena.localPosition : remotePlayer
            let direction = side == .left ? arena.localDirection : remoteDirection
            guard ArenaPhysics.backheel(&ball, from: position, direction: direction) else { return }
            if side == .right { remoteDirection = CGPoint(x: -direction.x, y: -direction.y) }
            kickoffOwner = nil
            sendScore(goal: false)
        }
        lastSpecialAt[side] = now
        arena.animateSpecial(move, local: side == .left)
        send(MatchMessage(kind: move == .stepover ? .stepover : .backheel, matchID: id, actorID: actorID))
    }

    private func marseille() {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side) else { return }
        guard ball.carrier == side else {
            arena.showFeedback("공을 소유해야 마르세유턴을 할 수 있어요")
            return
        }
        if isHost { beginMarseille(side: side, actorID: GameIdentity.localID) }
        else { send(MatchMessage(kind: .marseille, matchID: id)) }
    }

    private func beginMarseille(side: FieldEdge, actorID: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        guard isHost, let id = matchID, canAct(side: side), ball.carrier == side,
              now - lastTurnAt > 1.5 else { return }
        lastTurnAt = now
        arena.startMarseille(local: side == .left)
        send(MatchMessage(kind: .marseille, matchID: id, actorID: actorID))
    }

    private func rainbow() {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side) else { return }
        guard ball.carrier == side else { arena.showFeedback("공을 소유해야 사포를 할 수 있어요"); return }
        if isHost { beginRainbow(side: side, actorID: GameIdentity.localID) }
        else { send(MatchMessage(kind: .rainbow, matchID: id)) }
    }

    private func beginRainbow(side: FieldEdge, actorID: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        let position = side == .left ? arena.localPosition : remotePlayer
        let direction = side == .left ? arena.localDirection : remoteDirection
        guard isHost, let id = matchID, canAct(side: side), ball.carrier == side,
              now - lastRainbowAt > 1.2,
              ArenaPhysics.rainbow(&ball, from: position, direction: direction) else { return }
        lastRainbowAt = now
        arena.animateRainbow(local: side == .left)
        send(MatchMessage(kind: .rainbow, matchID: id, actorID: actorID))
    }

    private func phantom(vertical: Double) {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side), ball.carrier == side else {
            arena.showFeedback("공을 소유해야 팬텀 드리블을 할 수 있어요")
            return
        }
        if isHost { beginPhantom(side: side, actorID: GameIdentity.localID, vertical: vertical) }
        else { send(MatchMessage(kind: .phantom, matchID: id, y: vertical)) }
    }

    private func beginPhantom(side: FieldEdge, actorID: UUID, vertical: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard isHost, let id = matchID, canAct(side: side), ball.carrier == side,
              now - lastPhantomAt > 0.9 else { return }
        lastPhantomAt = now
        arena.startPhantom(local: side == .left, vertical: vertical)
        send(MatchMessage(kind: .phantom, matchID: id, y: vertical, actorID: actorID))
    }

    private func powerShot(from position: CGPoint) {
        guard let id = matchID else { return }
        let side: FieldEdge = isHost ? .left : .right
        guard canAct(side: side), ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side) else { return }
        guard hypot(ball.x - position.x, ball.y - position.y) < 0.075 else {
            arena.showFeedback("공에 더 가까이 가세요!")
            return
        }
        if isHost {
            beginPowerShot(from: position, side: .left, actorID: GameIdentity.localID)
        } else {
            send(MatchMessage(kind: .powerShot, matchID: id))
        }
    }

    private func beginPowerShot(from position: CGPoint, side: FieldEdge, actorID: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        guard isHost, let id = matchID, canAct(side: side),
              ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: side),
              now - lastPowerAt > 2.5,
              hypot(ball.x - position.x, ball.y - position.y) < 0.075 else { return }
        lastPowerAt = now
        powerActorSide = side
        powerReleaseAt = now + 0.65
        fireUntil = powerReleaseAt + 0.9
        arena.startPowerCinematic(local: side == .left)
        send(MatchMessage(kind: .powerShot, matchID: id, actorID: actorID))
    }

    private func beginPowerVisual(side: FieldEdge) {
        let now = ProcessInfo.processInfo.systemUptime
        powerActorSide = side
        powerReleaseAt = now + 0.65
        fireUntil = powerReleaseAt + 0.9
        arena.startPowerCinematic(local: side == .right)
    }

    private func togglePause() {
        if pausedAt == nil { pause() }
        else { resume() }
    }

    private func pause(notifyPeer: Bool = true) {
        guard let id = matchID, pausedAt == nil else { return }
        pausedAt = ProcessInfo.processInfo.systemUptime
        arena.setPaused(true)
        if notifyPeer {
            let message = MatchMessage(kind: .pause, matchID: id)
            send(message)
        }
        render()
    }

    private func resume(notifyPeer: Bool = true) {
        guard let id = matchID, let pausedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - pausedAt
        self.pausedAt = nil
        startedAt += elapsed
        kickoffAt += elapsed
        if powerActorSide != nil { powerReleaseAt += elapsed }
        if fireUntil > pausedAt { fireUntil += elapsed }
        if goalNoticeUntil > 0 { goalNoticeUntil += elapsed }
        if leftFallenUntil > 0 { leftFallenUntil += elapsed }
        if rightFallenUntil > 0 { rightFallenUntil += elapsed }
        if lastKickAt > 0 { lastKickAt += elapsed }
        if lastTackleAt > 0 { lastTackleAt += elapsed }
        if lastPowerAt > 0 { lastPowerAt += elapsed }
        if lastTurnAt > 0 { lastTurnAt += elapsed }
        if lastRainbowAt > 0 { lastRainbowAt += elapsed }
        if lastPhantomAt > 0 { lastPhantomAt += elapsed }
        for side in Array(lastSpecialAt.keys) { lastSpecialAt[side]? += elapsed }
        lastTick = ProcessInfo.processInfo.systemUptime
        lastSyncSentAt = 0
        arena.setPaused(false, elapsed: elapsed)
        if notifyPeer {
            let message = MatchMessage(kind: .resume, matchID: id)
            send(message)
        }
        render()
    }

    private func sendScore(goal: Bool) {
        guard let id = matchID else { return }
        send(MatchMessage(kind: .sync, matchID: id, x: goal ? 1 : 0,
                          y: kickoffOwner == nil ? 2 : (kickoffOwner == .left ? 0 : 1),
                          scores: ["left": leftScore, "right": rightScore],
                          remaining: max(0, duration - ((pausedAt ?? ProcessInfo.processInfo.systemUptime) - startedAt))))
    }

    private func targetEndpoint() -> NWEndpoint? {
        if let roomPeerEndpoint { return roomPeerEndpoint }
        let peers = ScreenLayoutStore.load().screens.filter { !$0.isLocal && !$0.host.isEmpty }
        return peers.count == 1 ? transport.endpoint(for: peers[0].host) : nil
    }

    private func send(_ message: MatchMessage, reportFailure: Bool = false) {
        guard let endpoint = targetEndpoint() else { return }
        transport.send(message, to: endpoint) { [weak self] error in
            guard reportFailure, error != nil else { return }
            self?.onConnectionIssue?("상대 연결 실패")
            if message.kind == .start { self?.finish() }
        }
    }
}
