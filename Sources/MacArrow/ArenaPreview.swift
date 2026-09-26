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
    private var goalNoticeUntil: TimeInterval = 0

    init() {
        arena.onKick = { [weak self] position, direction in
            guard let self else { return }
            if !ArenaPhysics.kick(&self.ball, from: position, direction: direction) {
                self.arena.showFeedback("공에 더 가까이 가세요!")
            }
        }
        arena.onTackle = { [weak self] position, direction in
            guard let self else { return }
            _ = ArenaPhysics.tackle(&self.ball, from: position, direction: direction)
        }
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
        lastOpponentKickAt = 0
        goalNoticeUntil = 0
        startedAt = ProcessInfo.processInfo.systemUptime
        lastTick = startedAt
        arena.window?.title = "SIU — 경기장 미리보기 (AI 연습)"
        arena.show(homeSide: .left)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        arena.hide()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        arena.advance(dt: dt)
        let delta = CGPoint(x: ball.x - opponent.x, y: ball.y - opponent.y)
        let distance = hypot(delta.x, delta.y)
        let direction = distance > 0.001
            ? CGPoint(x: delta.x / distance, y: delta.y / distance) : CGPoint(x: -1, y: 0)
        if distance > 0.055 {
            opponent.x = min(max(opponent.x + direction.x * dt * 0.22, 0.065), 0.935)
            opponent.y = min(max(opponent.y + direction.y * dt * 0.22, 0.10), 0.90)
        }
        arena.setRemote(position: opponent, direction: direction)
        if now >= kickoffAt {
            if distance < 0.08, now - lastOpponentKickAt > 1.2,
               ArenaPhysics.kick(&ball, from: opponent, direction: CGPoint(x: -1, y: 0)) {
                lastOpponentKickAt = now
                arena.animateRemoteKick()
            }
            switch ArenaPhysics.step(&ball, dt: dt) {
            case .inPlay:
                ArenaPhysics.contact(&ball, player: arena.localPosition,
                                     direction: arena.localDirection)
                ArenaPhysics.contact(&ball, player: opponent, direction: direction)
            case .goalAtLeft:
                theirScore += 1
                resetAfterGoal(now: now)
            case .goalAtRight:
                myScore += 1
                resetAfterGoal(now: now)
            }
        }
        arena.render(ball: ball, myScore: myScore, theirScore: theirScore,
                     remaining: max(0, 300 - (now - startedAt)),
                     status: now < goalNoticeUntil ? "GOAL!" : "")
    }

    private func resetAfterGoal(now: TimeInterval) {
        ball = .kickoff
        kickoffAt = now + 1.4
        goalNoticeUntil = now + 2
    }
}
