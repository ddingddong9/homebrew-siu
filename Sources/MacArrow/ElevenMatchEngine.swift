import Foundation

struct ElevenInput {
    var horizontal: Double = 0
    var vertical: Double = 0
    var sprint = false
}

struct ElevenPlayer {
    let id: Int
    let side: FieldEdge
    let homeX: Double
    let homeY: Double
    let goalkeeper: Bool
    var x: Double
    var y: Double
    var facingX: Double
    var facingY: Double
    var fallenFor: Double = 0
    var kickFor: Double = 0
    var tackleFor: Double = 0
    var feintFor: Double = 0
    var feintLean: Double = 0
}

/// A screen-independent first slice of the 11-a-side simulation. The renderer reads
/// state, but never decides possession, goals, player selection, or AI movement.
struct ElevenMatchEngine {
    private(set) var players: [ElevenPlayer] = []
    private(set) var ball = ArenaBall.kickoff
    private(set) var leftScore = 0
    private(set) var rightScore = 0
    private(set) var remaining: TimeInterval = 300
    private(set) var selectedID = 9
    private(set) var kickoffFor: TimeInterval = 0.7
    private(set) var paused = false
    private var carrierID: Int?
    private var aiShotCooldown: TimeInterval = 0
    private var aiTackleCooldown: TimeInterval = 0
    private var feintCooldown: TimeInterval = 0
    private var feintSide = 1.0
    private let aiEnabled: Bool

    init(duration: TimeInterval = 300, aiEnabled: Bool = true) {
        remaining = duration
        self.aiEnabled = aiEnabled
        resetPositions(conceding: .left)
    }

    var finished: Bool { remaining <= 0 }
    var selected: ElevenPlayer { players[selectedID] }

    mutating func togglePause() { paused.toggle() }

    mutating func switchPlayer() {
        guard !paused, !finished else { return }
        let candidates = players.indices.filter { players[$0].side == .left && $0 != selectedID }
        guard let nearest = candidates.min(by: {
            hypot(players[$0].x - ball.x, players[$0].y - ball.y) <
                hypot(players[$1].x - ball.x, players[$1].y - ball.y)
        }) else { return }
        selectedID = nearest
    }

    mutating func pass() {
        guard canAct, ball.carrier == .left else { return }
        let source = selected
        guard let target = players.filter({ $0.side == .left && $0.id != selectedID })
            .max(by: { passScore($0, source: source) < passScore($1, source: source) }) else { return }
        let dx = target.x - ball.x
        let dy = target.y - ball.y
        guard hypot(dx, dy) > 0.025 else { return }
        if ArenaPhysics.kick(&ball, from: CGPoint(x: source.x, y: source.y),
                             direction: CGPoint(x: dx, y: dy), power: 0.7) {
            carrierID = nil
            players[selectedID].kickFor = 0.38
        }
    }

    mutating func shoot(curved: Bool = false) {
        guard canAct, ball.carrier == .left else { return }
        let source = selected
        let direction = CGPoint(x: source.facingX, y: source.facingY)
        if curved {
            if ArenaPhysics.curveKick(&ball, from: CGPoint(x: source.x, y: source.y),
                                      direction: direction, toward: .right) {
                carrierID = nil
                players[selectedID].kickFor = 0.38
            }
        } else {
            if ArenaPhysics.kick(&ball, from: CGPoint(x: source.x, y: source.y),
                                 direction: direction, aimToward: .right) {
                carrierID = nil
                players[selectedID].kickFor = 0.38
            }
        }
    }

    mutating func tackle() {
        guard canAct else { return }
        let source = selected
        players[selectedID].tackleFor = 0.36
        guard let opponent = players.indices.filter({ players[$0].side == .right })
            .min(by: {
                hypot(players[$0].x - source.x, players[$0].y - source.y) <
                    hypot(players[$1].x - source.x, players[$1].y - source.y)
            }), hypot(players[opponent].x - source.x, players[opponent].y - source.y) < 0.06 else { return }
        players[opponent].fallenFor = 0.8
        if ball.carrier == .right {
            ArenaPhysics.dispossess(&ball, direction: CGPoint(x: source.facingX, y: source.facingY))
            carrierID = nil
        }
    }

    mutating func feint() {
        guard canAct, ball.carrier == .left, carrierID == selectedID,
              feintCooldown == 0 else { return }
        let source = selected
        let side = feintSide
        feintSide *= -1
        players[selectedID].x = min(max(source.x - source.facingY * side * 0.045, 0.045), 0.955)
        players[selectedID].y = min(max(source.y + source.facingX * side * 0.045, 0.09), 0.91)
        players[selectedID].feintFor = 0.30
        players[selectedID].feintLean = side
        feintCooldown = 0.72
        ArenaPhysics.carry(&ball, beside: CGPoint(x: players[selectedID].x,
                                                  y: players[selectedID].y),
                           direction: CGPoint(x: source.facingX, y: source.facingY))
    }

    mutating func step(input: ElevenInput, dt rawDelta: TimeInterval) {
        guard !paused, !finished else { return }
        let dt = min(max(rawDelta, 0), 0.05)
        remaining = max(0, remaining - dt)
        kickoffFor = max(0, kickoffFor - dt)
        aiShotCooldown = max(0, aiShotCooldown - dt)
        aiTackleCooldown = max(0, aiTackleCooldown - dt)
        feintCooldown = max(0, feintCooldown - dt)
        for index in players.indices {
            players[index].fallenFor = max(0, players[index].fallenFor - dt)
            players[index].kickFor = max(0, players[index].kickFor - dt)
            players[index].tackleFor = max(0, players[index].tackleFor - dt)
            players[index].feintFor = max(0, players[index].feintFor - dt)
        }
        guard kickoffFor == 0 else { return }

        let magnitude = hypot(input.horizontal, input.vertical)
        if magnitude > 0.01 && players[selectedID].fallenFor == 0 {
            let dx = input.horizontal / magnitude
            let dy = input.vertical / magnitude
            let speed = input.sprint ? 0.20 : 0.14
            players[selectedID].x = min(max(players[selectedID].x + dx * speed * dt, 0.045), 0.955)
            players[selectedID].y = min(max(players[selectedID].y + dy * speed * dt, 0.09), 0.91)
            players[selectedID].facingX = dx
            players[selectedID].facingY = dy
        }
        if aiEnabled {
            moveAI(dt: dt)
            challengeCarrier()
        }

        if let carrierID, ball.carrier != nil {
            let player = players[carrierID]
            ArenaPhysics.carry(&ball, beside: CGPoint(x: player.x, y: player.y),
                               direction: CGPoint(x: player.facingX, y: player.facingY))
        }
        defendGoal()
        switch ArenaPhysics.step(&ball, dt: dt) {
        case .goalAtLeft:
            if (0.445...0.555).contains(ball.y) {
                rightScore += 1
                resetPositions(conceding: .left)
            } else { reboundFromGoalLine(at: .left) }
        case .goalAtRight:
            if (0.445...0.555).contains(ball.y) {
                leftScore += 1
                resetPositions(conceding: .right)
            } else { reboundFromGoalLine(at: .right) }
        case .inPlay:
            if ball.carrier == nil { captureNearestPlayer() }
        }
    }

    private var canAct: Bool { !paused && !finished && kickoffFor == 0 && players[selectedID].fallenFor == 0 }

    private func passScore(_ target: ElevenPlayer, source: ElevenPlayer) -> Double {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = hypot(dx, dy)
        guard distance > 0.025 else { return -.infinity }
        let alignment = (dx * source.facingX + dy * source.facingY) / distance
        return alignment * 2 - abs(distance - 0.22)
    }

    private mutating func moveAI(dt: TimeInterval) {
        for side in [FieldEdge.left, .right] {
            let eligible = players.indices.filter { players[$0].side == side &&
                $0 != selectedID && !players[$0].goalkeeper && players[$0].fallenFor == 0 }
            let pursuer = eligible.min(by: {
                hypot(players[$0].x - ball.x, players[$0].y - ball.y) <
                    hypot(players[$1].x - ball.x, players[$1].y - ball.y)
            })
            for index in players.indices where players[index].side == side && index != selectedID {
                guard players[index].fallenFor == 0 else { continue }
                let ownsBall = ball.carrier == side
                let isCarrier = ownsBall && index == carrierID
                let isPursuer = !ownsBall && index == pursuer
                let player = players[index]
                let shift = (ball.x - 0.5) * 0.15
                let targetX: Double
                let targetY: Double
                if player.goalkeeper {
                    targetX = side == .left ? 0.07 : 0.93
                    targetY = min(max(ball.y, 0.38), 0.62)
                } else if isCarrier {
                    targetX = side == .left ? 0.94 : 0.06
                    targetY = min(max(player.y + (0.5 - player.y) * 0.15, 0.13), 0.87)
                } else if isPursuer {
                    targetX = ball.x
                    targetY = ball.y
                } else {
                    targetX = min(max(player.homeX + shift, 0.07), 0.93)
                    targetY = player.homeY
                }
                let dx = targetX - player.x
                let dy = targetY - player.y
                let distance = hypot(dx, dy)
                guard distance > 0.003 else { continue }
                let step = min(distance, (isPursuer ? 0.13 : 0.09) * dt)
                players[index].x = min(max(player.x + dx / distance * step, 0.045), 0.955)
                players[index].y = min(max(player.y + dy / distance * step, 0.09), 0.91)
                if isCarrier || isPursuer {
                    players[index].facingX = dx / distance
                    players[index].facingY = dy / distance
                }
            }
        }
        if ball.carrier == .right, let carrierID, players[carrierID].x < 0.34,
           aiShotCooldown == 0 {
            let striker = players[carrierID]
            if ArenaPhysics.kick(&ball, from: CGPoint(x: striker.x, y: striker.y),
                                 direction: CGPoint(x: -1, y: 0), aimToward: .left) {
                aiShotCooldown = 1.5
                self.carrierID = nil
                players[carrierID].kickFor = 0.38
            }
        }
    }

    private mutating func captureNearestPlayer() {
        guard let closest = players.indices.filter({ players[$0].fallenFor == 0 })
            .min(by: {
                hypot(players[$0].x - ball.x, players[$0].y - ball.y) <
                    hypot(players[$1].x - ball.x, players[$1].y - ball.y)
            }) else { return }
        let player = players[closest]
        if ArenaPhysics.capture(&ball, by: player.side, player: CGPoint(x: player.x, y: player.y)) {
            carrierID = closest
            if player.side == .left { selectedID = closest }
        }
    }

    private mutating func challengeCarrier() {
        guard aiTackleCooldown == 0, let carrierID, let carrier = ball.carrier else { return }
        let closest = players.indices.filter {
            players[$0].side != carrier && $0 != selectedID && players[$0].fallenFor == 0
        }.min(by: {
            hypot(players[$0].x - ball.x, players[$0].y - ball.y) <
                hypot(players[$1].x - ball.x, players[$1].y - ball.y)
        })
        guard players[carrierID].feintFor == 0, let closest,
              hypot(players[closest].x - ball.x, players[closest].y - ball.y) <
                (players[closest].goalkeeper ? 0.07 : 0.032) else { return }
        let direction = carrier == .left ? -1.0 : 1.0
        ArenaPhysics.dispossess(&ball, direction: CGPoint(x: direction, y: 0))
        players[carrierID].fallenFor = 0.35
        players[closest].tackleFor = 0.36
        self.carrierID = nil
        aiTackleCooldown = 1.1
    }

    private mutating func reboundFromGoalLine(at side: FieldEdge) {
        ball.carrier = nil
        carrierID = nil
        ball.x = side == .left ? 0.04 : 0.96
        ball.vx = (side == .left ? 1 : -1) * max(abs(ball.vx) * 0.6, 0.14)
        ball.recatchDelay = 0.25
    }

    private mutating func defendGoal() {
        guard ball.carrier == nil, ball.z < 0.12 else { return }
        for side in [FieldEdge.left, .right] {
            guard let keeper = players.indices.first(where: {
                players[$0].side == side && players[$0].goalkeeper
            }) else { continue }
            let approaching = side == .left ? ball.vx < -0.2 && ball.x < 0.14 :
                ball.vx > 0.2 && ball.x > 0.86
            guard approaching, abs(ball.y - players[keeper].y) < 0.034 else { continue }
            ball.vx = (side == .left ? 1 : -1) * max(abs(ball.vx) * 0.68, 0.25)
            ball.vy += ball.y < 0.5 ? -0.14 : 0.14
            ball.recatchDelay = 0.22
            players[keeper].kickFor = 0.38
            break
        }
    }

    private mutating func resetPositions(conceding side: FieldEdge) {
        let formation: [(Double, Double)] = [
            (0.07, 0.5),
            (0.22, 0.18), (0.22, 0.39), (0.22, 0.61), (0.22, 0.82),
            (0.34, 0.25), (0.34, 0.5), (0.34, 0.75),
            (0.44, 0.22), (0.44, 0.5), (0.44, 0.78)
        ]
        players = [FieldEdge.left, .right].flatMap { team in
            formation.enumerated().map { number, home in
                let x = team == .left ? home.0 : 1 - home.0
                return ElevenPlayer(id: (team == .left ? 0 : 11) + number,
                                    side: team, homeX: x, homeY: home.1,
                                    goalkeeper: number == 0, x: x, y: home.1,
                                    facingX: team == .left ? 1 : -1, facingY: 0)
            }
        }
        let kickoffID = side == .left ? 9 : 20
        players[kickoffID].x = side == .left ? 0.47 : 0.53
        players[kickoffID].y = 0.5
        selectedID = side == .left ? kickoffID : 9
        ball = .kickoff
        carrierID = nil
        kickoffFor = 1.3
    }
}
