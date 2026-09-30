import AppKit

@MainActor
final class ArenaPreviewController {
    private let arena = ArenaWindowController()
    private var timer: Timer?
    private var ball = ArenaBall.kickoff
    private var opponent = CGPoint(x: 0.75, y: 0.5)
    private var lastTick: TimeInterval = 0
    private var myScore = 0
    private var theirScore = 0
    private var startedAt: TimeInterval = 0
    private var kickoffAt: TimeInterval = 0
    private var lastOpponentKickAt: TimeInterval = 0
    private var lastOpponentTackleAt: TimeInterval = 0
    private var goalNoticeUntil: TimeInterval = 0
    private var kickoffOwner: FieldEdge? = .left
    private var opponentFallenUntil: TimeInterval = 0
    private var pausedAt: TimeInterval?
    private var powerReleaseAt: TimeInterval = 0
    private var powerPending = false
    private var fireUntil: TimeInterval = 0
    private var lastTurnAt: TimeInterval = 0
    private var lastRainbowAt: TimeInterval = 0
    private var lastPhantomAt: TimeInterval = 0
    private var lastStepoverAt: TimeInterval = -.infinity
    private var lastBackheelAt: TimeInterval = -.infinity
    var isRunning: Bool { timer != nil }
    var onStopped: (() -> Void)?

    init() {
        arena.onKick = { [weak self] position, direction in
            guard let self else { return }
            guard self.canAct, !self.powerPending,
                  ProcessInfo.processInfo.systemUptime >= self.kickoffAt,
                  ArenaPhysics.mayTakeKickoff(owner: self.kickoffOwner, player: .left) else { return }
            if !ArenaPhysics.kick(&self.ball, from: position, direction: direction,
                                  aimToward: .right) {
                self.arena.showFeedback("공에 더 가까이 가세요!")
            } else { self.kickoffOwner = nil }
        }
        arena.onCurveShot = { [weak self] position, direction in
            guard let self else { return }
            guard self.canAct, !self.powerPending,
                  ProcessInfo.processInfo.systemUptime >= self.kickoffAt,
                  ArenaPhysics.mayTakeKickoff(owner: self.kickoffOwner, player: .left) else { return }
            if !ArenaPhysics.curveKick(&self.ball, from: position, direction: direction,
                                       toward: .right) {
                self.arena.showFeedback("공에 더 가까이 가세요!")
            } else { self.kickoffOwner = nil }
        }
        arena.onTackle = { [weak self] position, direction in
            guard let self else { return }
            guard self.canAct, self.kickoffOwner == nil else { return }
            _ = ArenaPhysics.tackle(&self.ball, from: position, direction: direction)
            if hypot(position.x - self.opponent.x, position.y - self.opponent.y) < 0.08 {
                self.opponentFallenUntil = ProcessInfo.processInfo.systemUptime + 1.55
                self.arena.stunRemote()
            }
        }
        arena.onPowerShot = { [weak self] position in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.canAct, !self.powerPending, now >= self.kickoffAt,
                  ArenaPhysics.mayTakeKickoff(owner: self.kickoffOwner, player: .left),
                  hypot(self.ball.x - position.x, self.ball.y - position.y) < 0.075 else { return }
            self.powerPending = true
            self.powerReleaseAt = now + 0.65
            self.fireUntil = self.powerReleaseAt + 0.9
            self.arena.startPowerCinematic(local: true)
        }
        arena.onMarseille = { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.canAct, !self.powerPending, now >= self.kickoffAt,
                  now - self.lastTurnAt > 1.5 else { return }
            guard self.ball.carrier == .left else {
                self.arena.showFeedback("공을 소유해야 마르세유턴을 할 수 있어요")
                return
            }
            self.lastTurnAt = now
            self.arena.startMarseille(local: true)
        }
        arena.onRainbow = { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.canAct, !self.powerPending, now >= self.kickoffAt,
                  now - self.lastRainbowAt > 1.2 else { return }
            guard self.ball.carrier == .left else {
                self.arena.showFeedback("공을 소유해야 사포를 할 수 있어요")
                return
            }
            if ArenaPhysics.rainbow(&self.ball, from: self.arena.localPosition,
                                    direction: self.arena.localDirection) {
                self.lastRainbowAt = now
                self.arena.animateRainbow(local: true)
            }
        }
        arena.onPhantom = { [weak self] vertical in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.canAct, !self.powerPending, now >= self.kickoffAt,
                  now - self.lastPhantomAt > 0.9 else { return }
            guard self.ball.carrier == .left else {
                self.arena.showFeedback("공을 소유해야 팬텀 드리블을 할 수 있어요")
                return
            }
            self.lastPhantomAt = now
            self.arena.startPhantom(local: true, vertical: vertical)
        }
        arena.onPauseToggle = { [weak self] in self?.togglePause() }
        arena.onStepover = { [weak self] in
            guard let self, self.canAct else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.ball.carrier == .left else { self.arena.showFeedback("공을 소유해야 발재간을 할 수 있어요"); return }
            guard now - self.lastStepoverAt > 1.4 else { return }
            self.lastStepoverAt = now
            self.arena.animateSpecial(.stepover, local: true)
        }
        arena.onBackheel = { [weak self] in
            guard let self, self.canAct else { return }
            guard ArenaPhysics.mayTakeKickoff(owner: self.kickoffOwner, player: .left) else { self.arena.showFeedback("상대 선공입니다"); return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - self.lastBackheelAt > 0.9 else { return }
            guard ArenaPhysics.backheel(&self.ball, from: self.arena.localPosition, direction: self.arena.localDirection) else {
                self.arena.showFeedback("공에 가까이 가서 Q를 누르세요"); return
            }
            self.lastBackheelAt = now
            self.kickoffOwner = nil
            self.arena.animateSpecial(.backheel, local: true)
        }
        arena.onResume = { [weak self] in self?.resume() }
        arena.onEnd = { [weak self] in self?.stop() }
        arena.onClose = { [weak self] in self?.stop() }
    }

    func show() {
        guard timer == nil else {
            arena.window?.makeKeyAndOrderFront(nil)
            return
        }
        ball = .kickoff
        opponent = CGPoint(x: 0.75, y: 0.5)
        myScore = 0
        theirScore = 0
        kickoffAt = 0
        kickoffOwner = .left
        lastOpponentKickAt = 0
        lastOpponentTackleAt = 0
        goalNoticeUntil = 0
        opponentFallenUntil = 0
        pausedAt = nil
        powerPending = false
        lastStepoverAt = -.infinity
        lastBackheelAt = -.infinity
        fireUntil = 0
        lastTurnAt = 0
        lastRainbowAt = 0
        lastPhantomAt = 0
        startedAt = ProcessInfo.processInfo.systemUptime
        lastTick = startedAt
        arena.window?.title = "SIU — 경기장 미리보기 (AI 연습)"
        arena.show(homeSide: .left)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        let wasRunning = timer != nil
        timer?.invalidate()
        timer = nil
        pausedAt = nil
        arena.hide()
        if wasRunning { onStopped?() }
    }

    private var canAct: Bool {
        pausedAt == nil && !powerPending && ProcessInfo.processInfo.systemUptime >= kickoffAt &&
            !arena.isLocalFallen && arena.specialProgress(side: .left) == nil &&
            arena.marseilleProgress(side: .left) == nil && arena.phantomProgress(side: .left) == nil
    }

    private func togglePause() {
        if pausedAt == nil {
            pausedAt = ProcessInfo.processInfo.systemUptime
            arena.setPaused(true)
        } else { resume() }
    }

    private func resume() {
        guard let pausedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - pausedAt
        self.pausedAt = nil
        startedAt += elapsed
        kickoffAt += elapsed
        if goalNoticeUntil > 0 { goalNoticeUntil += elapsed }
        if opponentFallenUntil > 0 { opponentFallenUntil += elapsed }
        if powerPending { powerReleaseAt += elapsed; fireUntil += elapsed }
        if lastTurnAt > 0 { lastTurnAt += elapsed }
        if lastRainbowAt > 0 { lastRainbowAt += elapsed }
        if lastPhantomAt > 0 { lastPhantomAt += elapsed }
        if lastStepoverAt.isFinite { lastStepoverAt += elapsed }
        if lastBackheelAt.isFinite { lastBackheelAt += elapsed }
        lastTick = ProcessInfo.processInfo.systemUptime
        arena.setPaused(false, elapsed: elapsed)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        if pausedAt != nil {
            render(at: pausedAt!)
            return
        }
        if powerPending && now >= powerReleaseAt {
            powerPending = false
            if ArenaPhysics.powerKick(&ball, from: arena.localPosition, toward: .right) {
                kickoffOwner = nil
            }
        }
        arena.setFireBall(now >= powerReleaseAt && now < fireUntil)
        if now >= kickoffAt && !powerPending { arena.advance(dt: dt) }
        if let carrier = ball.carrier {
            ArenaPhysics.carry(&ball, beside: carrier == .left ? arena.localPosition : opponent,
                               direction: carrier == .left ? arena.localDirection : CGPoint(x: -1, y: 0),
                               turnProgress: arena.marseilleProgress(side: carrier),
                               stepoverProgress: arena.specialProgress(side: carrier, move: .stepover))
        }
        let delta = CGPoint(x: ball.x - opponent.x, y: ball.y - opponent.y)
        let distance = hypot(delta.x, delta.y)
        let direction = distance > 0.001
            ? CGPoint(x: delta.x / distance, y: delta.y / distance) : CGPoint(x: -1, y: 0)
        if now >= kickoffAt && !powerPending && now >= opponentFallenUntil && distance > 0.055 {
            opponent.x = min(max(opponent.x + direction.x * dt * 0.22, 0.065), 0.935)
            opponent.y = min(max(opponent.y + direction.y * dt * 0.22, 0.10), 0.90)
        }
        if now >= kickoffAt && ball.carrier == .right && now >= opponentFallenUntil {
            opponent.x = max(0.065, opponent.x - dt * 0.20)
            ArenaPhysics.carry(&ball, beside: opponent, direction: CGPoint(x: -1, y: 0))
        }
        arena.setRemote(position: opponent, direction: direction)
        if now >= kickoffAt && !powerPending {
            if now >= opponentFallenUntil && ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: .right),
               ball.carrier == .right, opponent.x < 0.30, now - lastOpponentKickAt > 1.2,
               ArenaPhysics.kick(&ball, from: opponent, direction: CGPoint(x: -1, y: 0)) {
                lastOpponentKickAt = now
                kickoffOwner = nil
                arena.animateRemoteKick()
            }
            if now >= opponentFallenUntil && kickoffOwner == nil,
               now - lastOpponentTackleAt > 3,
               arena.marseilleProgress(side: .left) == nil &&
               arena.phantomProgress(side: .left) == nil,
               hypot(opponent.x - arena.localPosition.x,
                     opponent.y - arena.localPosition.y) < 0.07 {
                lastOpponentTackleAt = now
                arena.animateRemoteTackle()
                arena.stun()
                _ = ArenaPhysics.tackle(&ball, from: opponent, direction: direction)
            }
            switch ArenaPhysics.step(&ball, dt: dt) {
            case .inPlay:
                if ball.carrier == nil && ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: .left),
                   ArenaPhysics.capture(&ball, by: .left, player: arena.localPosition) {
                    ArenaPhysics.carry(&ball, beside: arena.localPosition, direction: arena.localDirection)
                    kickoffOwner = nil
                }
                if ball.carrier == nil && now >= opponentFallenUntil &&
                   ArenaPhysics.mayTakeKickoff(owner: kickoffOwner, player: .right),
                   ArenaPhysics.capture(&ball, by: .right, player: opponent) {
                    ArenaPhysics.carry(&ball, beside: opponent, direction: direction)
                    kickoffOwner = nil
                }
                if ball.carrier == nil && hypot(ball.vx, ball.vy) >= 0.7 {
                    _ = ArenaPhysics.contact(&ball, player: arena.localPosition,
                                             direction: arena.localDirection)
                    _ = ArenaPhysics.contact(&ball, player: opponent, direction: direction)
                }
            case .goalAtLeft:
                theirScore += 1
                resetAfterGoal(now: now, conceding: .left)
            case .goalAtRight:
                myScore += 1
                resetAfterGoal(now: now, conceding: .right)
            }
        }
        render(at: now)
    }

    private func render(at now: TimeInterval) {
        arena.render(ball: ball, myScore: myScore, theirScore: theirScore,
                     remaining: max(0, 300 - (now - startedAt)),
                     status: now < goalNoticeUntil ? "GOAL!" :
                        now < kickoffAt ? (kickoffOwner == .left ? "내 선공" : "상대 선공") : "")
    }

    private func resetAfterGoal(now: TimeInterval, conceding side: FieldEdge) {
        ball = .kickoff
        kickoffOwner = side
        kickoffAt = now + SpecialMove.celebration.duration + 0.2
        goalNoticeUntil = kickoffAt
        fireUntil = 0
        arena.setFireBall(false)
        arena.resetForKickoff(conceding: side)
        arena.animateSpecial(.celebration, local: side == .right)
        opponent = CGPoint(x: ArenaPhysics.startingX(conceding: side).right, y: 0.5)
        arena.setRemote(position: opponent, direction: CGPoint(x: -1, y: 0))
    }
}
