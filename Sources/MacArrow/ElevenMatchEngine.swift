import Foundation

enum ElevenSide: String, Codable { case left, right
    var opposite: Self { self == .left ? .right : .left }
    var sign: Double { self == .left ? 1 : -1 }
}
enum FootballPitch {
    static let length = 105.0, width = 68.0, goalWidth = 7.32, goalHeight = 2.44
    static let ballRadius = 0.11, tick = 1.0 / 60.0
}
struct FootballVector: Codable {
    var x = 0.0, y = 0.0
    var length: Double { hypot(x, y) }
    var unit: Self { length > 0.00001 ? self / length : Self() }
    static func + (a: Self, b: Self) -> Self { Self(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { Self(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { Self(x: a.x * b, y: a.y * b) }
    static func / (a: Self, b: Double) -> Self { a * (1 / b) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y }
    func approaching(_ target: Self, by limit: Double) -> Self {
        let delta = target - self
        return self + delta.unit * min(limit, delta.length)
    }
}
struct FootballBall: Codable {
    var x = 52.5, y = 34.0, z = FootballPitch.ballRadius
    var vx = 0.0, vy = 0.0, vz = 0.0, curve = 0.0
    var carrier: ElevenSide?
    var recatchDelay = 0.0
    var heldBy: Int?
    var throwIn = false
    var heldFor = 0.0
    var throwGrace = 0.0
    var position: FootballVector { FootballVector(x: x, y: y) }
    var velocity: FootballVector { FootballVector(x: vx, y: vy) }
}
struct ElevenInput: Codable {
    var horizontal: Double = 0
    // +y is the near touchline / screen down.
    var vertical: Double = 0
    var sprint = false
}
enum FootballActionKind: String, Codable { case pass, shot, cross, tackle, standing, feint, roulette, rainbow, keeperThrow, throwIn, dive }
struct FootballAction: Codable {
    var kind: FootballActionKind
    var elapsed = 0.0
    var contacted = false
    var direction: FootballVector
    var power = 0.0
    var curve = 0.0
    var receiver: Int?
    var loft = 0.25
    var contactTime: Double {
        switch kind {
        case .tackle, .standing: return 0.12
        case .keeperThrow, .throwIn: return 0.38
        default: return 0.18
        }
    }
    var duration: Double {
        switch kind {
        case .pass, .standing: return 0.46
        case .shot, .cross: return 0.58
        case .tackle: return 0.72
        case .feint: return 0.42
        case .roulette: return 0.65
        case .rainbow: return 0.6
        case .keeperThrow, .throwIn: return 0.8
        case .dive: return 1.05
        }
    }
}
struct ElevenPlayer: Codable {
    let id: Int
    let side: ElevenSide
    let homeX: Double
    let homeY: Double
    let goalkeeper: Bool
    var x: Double
    var y: Double
    var facingX: Double
    var facingY: Double
    var vx = 0.0, vy = 0.0, gait = 0.0
    var fallenFor = 0.0, cooldown = 0.0, touchCooldown = 0.0
    var action: FootballAction?
    var position: FootballVector { FootballVector(x: x, y: y) }
    var velocity: FootballVector { FootballVector(x: vx, y: vy) }
    var facing: FootballVector { FootballVector(x: facingX, y: facingY) }
    var speed: Double { velocity.length }
}
struct ElevenSnapshot: Codable {
    var players: [ElevenPlayer]
    var ball: FootballBall
    var leftScore: Int, rightScore: Int, selectedID: Int, rightSelectedID: Int, tick: Int
    var remaining: Double, kickoffFor: Double
    var paused: Bool
    var restartLabel: String
    var valid: Bool {
        players.count == 22 && Set(players.map(\.id)) == Set(0..<22) &&
        players.enumerated().allSatisfy { i, p in
            p.id == i && p.side == (i < 11 ? .left : .right) &&
            [p.x, p.y, p.vx, p.vy, p.facingX, p.facingY, p.gait, p.fallenFor, p.cooldown, p.touchCooldown].allSatisfy { $0.isFinite && abs($0) < 1_000_000 } &&
            (p.action.map { a in
                [a.elapsed, a.power, a.curve, a.loft, a.direction.x, a.direction.y].allSatisfy { $0.isFinite && abs($0) < 1000 } &&
                (a.receiver.map { (0..<22).contains($0) } ?? true)
            } ?? true)
        } && (0..<11).contains(selectedID) && (11..<22).contains(rightSelectedID) &&
        [ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz, ball.curve, ball.heldFor, ball.recatchDelay, remaining, kickoffFor].allSatisfy { $0.isFinite && abs($0) < 100_000 } &&
        (ball.heldBy.map { (0..<22).contains($0) } ?? true) && remaining >= 0 && tick >= 0
    }
}

/// Metres/seconds, independent of ArenaPhysics and any rendering or networking API.
struct ElevenMatchEngine {
    private(set) var players: [ElevenPlayer] = []
    private(set) var ball = FootballBall()
    private(set) var previousPlayers: [ElevenPlayer] = []
    private(set) var previousBall = FootballBall()
    private(set) var leftScore = 0, rightScore = 0
    private(set) var remaining: Double
    private(set) var selectedID = 9, rightSelectedID = 20
    private(set) var kickoffFor = 0.0
    private(set) var paused = false
    private(set) var carrierID: Int?
    private(set) var restartLabel = "킥오프"
    private(set) var contactCount = 0, simulationTicks = 0
    var remoteControlled = false
    private var accumulator = 0.0
    private var lastTouch: ElevenSide = .left
    private var feintSide = 1.0
    private(set) var receiverID: Int?
    private var receiveAssist = 0.0
    private var receptionPoint = FootballVector()
    private let aiEnabled: Bool

    init(duration: Double = 300, aiEnabled: Bool = true) {
        remaining = max(1, duration)
        self.aiEnabled = aiEnabled
        resetPositions(conceding: .left)
        synchronizePresentation()
    }
    /// Reproducible local scenarios/replays; never called for client inputs.
    init(scenario: ElevenSnapshot, aiEnabled: Bool = false) {
        self.init(duration: scenario.remaining, aiEnabled: aiEnabled)
        guard scenario.valid else { return }
        apply(scenario)
        carrierID = players.filter { $0.side == ball.carrier }.min {
            ($0.position - ball.position).length < ($1.position - ball.position).length
        }?.id
        synchronizePresentation()
    }
    var finished: Bool { remaining <= 0 }
    var selected: ElevenPlayer { players[selectedID] }
    var interpolation: Double { paused || finished ? 1 : min(1, accumulator / FootballPitch.tick) }
    var snapshot: ElevenSnapshot {
        ElevenSnapshot(players: players, ball: ball, leftScore: leftScore, rightScore: rightScore,
                       selectedID: selectedID, rightSelectedID: rightSelectedID, tick: simulationTicks,
                       remaining: remaining, kickoffFor: kickoffFor, paused: paused, restartLabel: restartLabel)
    }
    mutating func apply(_ state: ElevenSnapshot) {
        guard state.valid else { return }
        previousPlayers = players; previousBall = ball
        players = state.players; ball = state.ball
        carrierID = ball.heldBy ?? players.filter { $0.side == ball.carrier }.min {
            ($0.position - ball.position).length < ($1.position - ball.position).length
        }?.id
        leftScore = state.leftScore; rightScore = state.rightScore
        selectedID = state.selectedID; rightSelectedID = state.rightSelectedID
        remaining = state.remaining; kickoffFor = state.kickoffFor
        paused = state.paused; restartLabel = state.restartLabel; simulationTicks = state.tick
    }
    mutating func togglePause() {
        paused.toggle(); accumulator = 0; synchronizePresentation()
    }
    func selection(_ side: ElevenSide) -> Int { side == .left ? selectedID : rightSelectedID }
    mutating func switchPlayer(side: ElevenSide = .left) {
        guard !paused, !finished else { return }
        let candidates = players.filter { $0.side == side && $0.id != selection(side) && !$0.goalkeeper }
        if let p = candidates.min(by: {
            ($0.position - ball.position).length < ($1.position - ball.position).length
        }) { select(p.id, side: side) }
    }
    mutating func pass(side: ElevenSide = .left, power: Double = 0.45) { beginPass(selection(side), charge: power) }
    mutating func cross(side: ElevenSide = .left, power: Double = 0.45) { beginPass(selection(side), charge: power, cross: true) }
    mutating func shoot(curved: Bool = false, side: ElevenSide = .left, power: Double = 0.55) {
        if ball.heldBy == selection(side) { beginPass(selection(side), charge: power, cross: true) }
        else { beginShot(selection(side), curved: curved, charge: power) }
    }
    func hasPossession(_ side: ElevenSide) -> Bool { carrierID == selection(side) || ball.heldBy == selection(side) }
    mutating func tackle(side: ElevenSide = .left, sliding: Bool = true) {
        let id = selection(side)
        guard canAct(id), carrierID != id else { return }
        players[id].action = FootballAction(kind: sliding ? .tackle : .standing, direction: players[id].facing)
    }
    mutating func feint(side: ElevenSide = .left) {
        let id = selection(side)
        guard canAct(id), carrierID == id else { return }
        let p = players[id]
        let direction = FootballVector(x: -p.facingY * feintSide, y: p.facingX * feintSide)
        feintSide *= -1
        players[id].action = FootballAction(kind: .feint, direction: direction)
    }
    mutating func skill(_ kind: FootballActionKind, side: ElevenSide = .left) {
        let id = selection(side)
        guard [.roulette, .rainbow].contains(kind), canAct(id), carrierID == id, ball.heldBy == nil else { return }
        players[id].action = FootballAction(kind: kind, direction: players[id].facing)
    }
    /// A 200 ms stall executes all 12 ticks rather than discarding elapsed time.
    /// The window pauses long suspensions before calling this method.
    mutating func step(input: ElevenInput, dt: Double, remoteInput: ElevenInput = ElevenInput()) {
        guard !paused, !finished, dt.isFinite, dt > 0 else { return }
        accumulator += dt
        while accumulator + 1e-10 >= FootballPitch.tick && !finished {
            previousPlayers = players; previousBall = ball
            simulate(input: input, remoteInput: remoteInput, dt: FootballPitch.tick)
            accumulator = max(0, accumulator - FootballPitch.tick)
        }
    }
    private func canAct(_ id: Int) -> Bool {
        !paused && !finished && kickoffFor == 0 && players[id].fallenFor == 0 &&
            players[id].action == nil && players[id].cooldown == 0
    }
    private mutating func select(_ id: Int, side: ElevenSide) {
        if side == .left { selectedID = id } else { rightSelectedID = id }
    }
    private mutating func beginPass(_ id: Int, charge: Double = 0.45, cross: Bool = false) {
        guard canAct(id), carrierID == id else { return }
        let p = players[id]
        let charge = min(1, max(0, charge.isFinite ? charge : 0.45))
        let desiredRange = (cross ? 15.0 : 7.0) + charge * (cross ? 30 : 24)
        func score(_ target: ElevenPlayer) -> Double {
            let d = target.position - p.position
            return d.unit.dot(p.facing) * 4 - abs(d.length - desiredRange) * 0.15
        }
        guard let target = players.filter({ $0.side == p.side && $0.id != id && !$0.goalkeeper && $0.fallenFor == 0 })
            .max(by: { score($0) < score($1) }) else { return }
        let kind: FootballActionKind = ball.throwIn ? .throwIn : ball.heldBy == id ? .keeperThrow : cross ? .cross : .pass
        let d = target.position - ball.position
        players[id].action = FootballAction(kind: kind, direction: d.unit, power: charge, receiver: target.id)
        // Selection changes immediately, but the original kicker finishes his contact animation.
        receiverID = target.id; receiveAssist = 4; receptionPoint = target.position
        select(target.id, side: p.side)
    }
    private mutating func beginShot(_ id: Int, curved: Bool = false, charge: Double = 0.55) {
        guard canAct(id), carrierID == id else { return }
        let p = players[id]
        let goal = FootballVector(x: p.side == .left ? 105 : 0, y: 34)
        let aim = (goal - ball.position).unit
        let charge = min(1, max(0, charge.isFinite ? charge : 0.55))
        let curve = curved ? (p.y < 34 ? 0.24 : -0.24) : 0
        // Even a tapped shot must feel decisive; held shots retain a clear power range.
        let speed = 18 + charge * 20
        // Aim the curved trajectory at the goal, compensating its initial side offset.
        let flight = min(2, (goal - ball.position).length / speed)
        let angle = atan2(aim.y, aim.x) - curve * flight * 0.4
        let direction = curved ? FootballVector(x: cos(angle), y: sin(angle)) : (p.facing * 0.22 + aim * 0.78).unit
        players[id].action = FootballAction(kind: .shot, direction: direction, power: speed,
                                             curve: curve, loft: 0.9 + charge * 3.2)
    }
    private mutating func simulate(input: ElevenInput, remoteInput: ElevenInput, dt: Double) {
        simulationTicks += 1
        if kickoffFor > 0 {
            kickoffFor = max(0, kickoffFor - dt)
            if kickoffFor == 0 && !ball.throwIn { restartLabel = "" }
            return
        }
        remaining = max(0, remaining - dt)
        ball.recatchDelay = max(0, ball.recatchDelay - dt)
        ball.throwGrace = max(0, ball.throwGrace - dt)
        receiveAssist = max(0, receiveAssist - dt)
        if receiveAssist == 0 { receiverID = nil }
        if ball.heldBy != nil { ball.heldFor += dt }
        for i in players.indices {
            players[i].fallenFor = max(0, players[i].fallenFor - dt)
            players[i].cooldown = max(0, players[i].cooldown - dt)
            players[i].touchCooldown = max(0, players[i].touchCooldown - dt)
        }
        let targets = aiEnabled ? aiTargets() : [:]
        for i in players.indices {
            let direction: FootballVector
            let sprint: Bool
            if i == selectedID || (remoteControlled && i == rightSelectedID) {
                let command = i == selectedID ? input : remoteInput
                let manual = FootballVector(x: command.horizontal, y: command.vertical).unit
                if manual.length == 0 && receiverID == i && receiveAssist > 0 && carrierID != i {
                    let target = carrierID == nil ? ball.position + ball.velocity * min(0.4, (players[i].position - ball.position).length / 18) : receptionPoint
                    let d = target - players[i].position
                    direction = d.unit * min(1, d.length / 1.2)
                } else { direction = manual }
                sprint = command.sprint
            } else if let target = targets[i] {
                let d = target - players[i].position
                direction = d.unit * min(1, d.length / 1.5)
                sprint = (players[i].position - ball.position).length < 12
            } else { direction = FootballVector(); sprint = false }
            movePlayer(i, direction: direction, sprint: sprint, dt: dt)
        }
        separatePlayers()
        advanceActions(dt: dt)
        dribble()
        advanceBall(dt: dt)
        if kickoffFor > 0 { synchronizePresentation(); return }
        receiveBall()
        if aiEnabled { chooseAIActions() }
        if let id = ball.heldBy, ball.heldFor > 7, canAct(id) { beginPass(id) }
    }
    private mutating func movePlayer(_ i: Int, direction: FootballVector, sprint: Bool, dt: Double) {
        var p = players[i]
        var target = direction * (sprint ? 7.2 : 4.8)
        if let a = p.action {
            switch a.kind {
            case .shot, .pass, .cross: target = target * (a.elapsed < a.contactTime ? 0.15 : 0.45)
            case .tackle: target = a.direction * (a.elapsed < 0.32 ? 8 : 0)
            case .standing: target = a.direction * (a.elapsed < 0.2 ? 1.5 : 0)
            case .feint: target = a.direction * 4.8 + p.facing * 1.8
            case .roulette:
                let angle = a.elapsed / a.duration * .pi * 2
                p.facingX = a.direction.x * cos(angle) - a.direction.y * sin(angle)
                p.facingY = a.direction.x * sin(angle) + a.direction.y * cos(angle)
                target = a.direction * 2.8
            case .rainbow: target = a.direction * 3.5
            case .dive: target = a.direction * (a.elapsed < 0.45 ? 4.5 : 0)
            case .keeperThrow, .throwIn: target = FootballVector()
            }
        }
        if ball.heldBy == i && ball.throwIn { p.vx = 0; p.vy = 0; players[i] = p; return }
        if ball.heldBy == i { target = target * 0.45 }
        if p.fallenFor > 0 { target = FootballVector() }
        let velocity = p.velocity.approaching(target, by: (target.length < p.speed ? 22 : 14) * dt)
        p.vx = velocity.x; p.vy = velocity.y
        if direction.length > 0.05 && p.fallenFor == 0 && p.action == nil {
            let angle = atan2(direction.y, direction.x), current = atan2(p.facingY, p.facingX)
            let delta = atan2(sin(angle - current), cos(angle - current))
            let limit = (9 - min(p.speed, 7.2) * 0.55) * dt
            let heading = current + min(max(delta, -limit), limit)
            p.facingX = cos(heading); p.facingY = sin(heading)
        }
        let old = p.position
        p.x = min(max(p.x + p.vx * dt, 0.35), 104.65)
        p.y = min(max(p.y + p.vy * dt, 0.35), 67.65)
        if p.x == 0.35 || p.x == 104.65 { p.vx = 0 }
        if p.y == 0.35 || p.y == 67.65 { p.vy = 0 }
        p.gait += (p.position - old).length / (sprint ? 2.8 : 2.2)
        players[i] = p
    }
    private mutating func separatePlayers() {
        for i in players.indices {
            for j in players.indices where j > i {
                if ball.throwIn && (ball.heldBy == i || ball.heldBy == j) { continue }
                let delta = players[j].position - players[i].position
                guard delta.length < 0.68 else { continue }
                let normal = delta.length > 0.001 ? delta.unit : FootballVector(x: 0, y: 1)
                let shift = normal * ((0.68 - delta.length) * 0.5)
                players[i].x = min(max(players[i].x - shift.x, 0.35), 104.65)
                players[i].y = min(max(players[i].y - shift.y, 0.35), 67.65)
                players[j].x = min(max(players[j].x + shift.x, 0.35), 104.65)
                players[j].y = min(max(players[j].y + shift.y, 0.35), 67.65)
            }
        }
    }
    private mutating func advanceActions(dt: Double) {
        for i in players.indices {
            guard var a = players[i].action else { continue }
            if players[i].fallenFor > 0 { players[i].action = nil; continue }
            a.elapsed += dt
            if !a.contacted && a.elapsed + 1e-9 >= a.contactTime {
                a.contacted = true
                if [.pass, .cross, .shot, .keeperThrow, .throwIn].contains(a.kind) {
                    if carrierID == i && (players[i].position - ball.position).length < 1.7 && (ball.z < 0.55 || ball.heldBy == i) {
                        if let receiver = a.receiver {
                            let target = players[receiver]
                            let lead = target.velocity * 0.3
                            receptionPoint = FootballVector(x: min(103, max(2, target.x + lead.x)), y: min(66, max(2, target.y + lead.y)))
                            let d = receptionPoint - ball.position
                            let charge = a.power
                            a.direction = d.unit
                            if a.kind == .pass {
                                // Solve v² = arrivalSpeed² + 2 * rollingResistance * distance.
                                a.power = sqrt(pow(6.5 + charge * 5, 2) + 2 * 2.6 * d.length)
                                a.loft = 0.1
                            } else if a.kind == .cross {
                                // Choose horizontal pace first, then solve the arc to the receiver.
                                // Fixed high loft made short crosses hang in the air unnecessarily.
                                a.power = 17 + charge * 13
                                let flight = -log(max(0.15, 1 - 0.1 * d.length / a.power)) / 0.1
                                a.loft = min(11, max(2, (0.11 - ball.z) / max(0.2, flight) + 4.905 * flight))
                            } else {
                                a.loft = 3.0 + charge * 3.5
                                let flight = (a.loft + sqrt(a.loft * a.loft + 19.62 * max(0, ball.z - 0.11))) / 9.81
                                a.power = min(32, d.length / max(0.5, flight) * 1.06)
                            }
                            receiveAssist = min(5, d.length / max(1, a.power) + 1.5)
                        }
                        ball.vx = a.direction.x * a.power; ball.vy = a.direction.y * a.power
                        ball.vz = a.loft; ball.curve = a.curve
                        releaseBall(delay: 0.32); lastTouch = players[i].side; contactCount += 1
                        restartLabel = ""
                    }
                }
                if a.kind == .rainbow && carrierID == i {
                    ball.vx = a.direction.x * 5.5; ball.vy = a.direction.y * 5.5; ball.vz = 5.8
                    releaseBall(delay: 0.55); lastTouch = players[i].side; contactCount += 1
                    receiverID = i; receiveAssist = 1.8
                }
                if a.kind == .standing && ball.heldBy == nil {
                    let foot = players[i].position + a.direction * 0.55
                    if (foot - ball.position).length < 0.8 && ball.z < 0.5 && ball.carrier != players[i].side {
                        // A standing challenge pokes the ball, never forces a fall.
                        ball.vx = a.direction.x * 3; ball.vy = a.direction.y * 3; ball.vz = 0
                        releaseBall(delay: 0.15); lastTouch = players[i].side
                    }
                }
            }
            if a.kind == .tackle && (0.12...0.34).contains(a.elapsed) && ball.heldBy == nil {
                let foot = players[i].position + a.direction * 0.65
                if (foot - ball.position).length < 0.7 && ball.z < 0.45 {
                    if let owner = carrierID, players[owner].side != players[i].side {
                        players[owner].fallenFor = 1.15; players[owner].action = nil
                    }
                    ball.vx = a.direction.x * 8; ball.vy = a.direction.y * 8; ball.vz = 1.2
                    releaseBall(delay: 0.4); lastTouch = players[i].side
                }
            }
            if a.elapsed >= a.duration {
                players[i].action = nil; players[i].cooldown = a.kind == .tackle ? 0.35 : 0.12
            } else { players[i].action = a }
        }
    }
    private mutating func dribble() {
        guard let i = carrierID else { return }
        if ball.heldBy == i { positionHeldBall(); return }
        let p = players[i]
        guard p.fallenFor == 0, (ball.position - p.position).length < 2.2, ball.z < 0.7 else {
            releaseBall(delay: 0.12); return
        }
        guard p.touchCooldown == 0 else { return }
        let forward = p.action?.kind == .feint ? (p.velocity.unit + p.facing).unit : p.facing
        let reach = 0.58 + min(p.speed / 7.2, 1) * 0.58
        let footSide = sin(p.gait * .pi * 2) >= 0 ? 0.13 : -0.13
        let foot = p.position + forward * reach + FootballVector(x: -forward.y, y: forward.x) * footSide
        if p.speed < 0.08 && (foot - ball.position).length < 0.16 {
            ball.vx = 0; ball.vy = 0; ball.vz = 0; ball.curve = 0
            return
        }
        // A tap changes velocity, never the ball's position.
        let desired = p.velocity + (foot - ball.position) * 4.5
        ball.vx = desired.x; ball.vy = desired.y; ball.curve = 0
        players[i].touchCooldown = p.action == nil ? (p.speed > 5 ? 0.14 : 0.19) : 0.08
        lastTouch = p.side
    }
    private mutating func releaseBall(delay: Double) {
        if ball.throwIn { ball.throwGrace = 0.8 }
        carrierID = nil; ball.carrier = nil; ball.recatchDelay = delay
        ball.heldBy = nil; ball.throwIn = false; ball.heldFor = 0
    }
    private mutating func positionHeldBall() {
        guard let id = ball.heldBy else { return }
        let p = players[id]
        var reach = 0.4, height = 1.15
        if ball.throwIn {
            let t = p.action?.elapsed ?? 0
            reach = t < 0.2 ? -0.2 : 0.15; height = t < 0.2 ? 1.7 : 1.95
        }
        ball.x = p.x + p.facingX * reach; ball.y = p.y + p.facingY * reach
        ball.z = height; ball.vx = 0; ball.vy = 0; ball.vz = 0
    }
    private mutating func advanceBall(dt: Double) {
        if ball.heldBy != nil { positionHeldBall(); return }
        let count = max(1, Int(ceil(ball.velocity.length * dt / 0.12)))
        let h = dt / Double(count)
        for _ in 0..<count {
            let old = ball, vx = ball.vx
            ball.vx += -ball.vy * ball.curve * h; ball.vy += vx * ball.curve * h
            ball.curve *= exp(-0.65 * h)
            ball.x += ball.vx * h; ball.y += ball.vy * h
            ball.vz -= 9.81 * h; ball.z += ball.vz * h
            if ball.z < FootballPitch.ballRadius {
                ball.z = FootballPitch.ballRadius
                ball.vz = abs(ball.vz) > 0.8 ? -ball.vz * 0.48 : 0
                let rolling = ball.velocity.approaching(FootballVector(), by: 2.6 * h)
                ball.vx = rolling.x; ball.vy = rolling.y
                if rolling.length < 0.08 { ball.vx = 0; ball.vy = 0; ball.curve = 0 }
            } else { ball.vx *= exp(-0.10 * h); ball.vy *= exp(-0.10 * h) }
            collidePosts()
            saveBall(from: old)
            if ball.heldBy != nil { return }
            if resolveBoundary(from: old) { return }
        }
    }
    private mutating func collidePosts() {
        for x in [0.0, 105.0] {
            for y in [30.34, 37.66] where ball.z < 2.55 {
                let d = ball.position - FootballVector(x: x, y: y)
                guard d.length < 0.17 else { continue }
                let n = d.length > 0.001 ? d.unit : FootballVector(x: 1, y: 0)
                let dot = ball.velocity.dot(n)
                if dot < 0 { ball.vx -= 1.72 * dot * n.x; ball.vy -= 1.72 * dot * n.y }
                ball.x = x + n.x * 0.17; ball.y = y + n.y * 0.17
                releaseBall(delay: 0.1)
            }
            if abs(ball.x - x) < 0.17 && abs(ball.y - 34) < 3.66 && abs(ball.z - 2.44) < 0.17 {
                ball.vx *= -0.72; ball.x = x + (x == 0 ? 0.18 : -0.18)
                releaseBall(delay: 0.1)
            }
        }
    }
    private mutating func saveBall(from old: FootballBall) {
        guard carrierID == nil, ball.recatchDelay == 0 else { return }
        for p in players where p.goalkeeper && p.fallenFor == 0 && p.cooldown == 0 {
            // Hands are only legal inside this keeper's own penalty area.
            guard (p.side == .left ? ball.x < 16.5 : ball.x > 88.5), abs(ball.y - 34) < 20.16 else { continue }
            let goalward = ball.vx * p.side.sign < -1
            if p.action == nil && goalward && ball.velocity.length > 8 {
                let arrival = (p.x - ball.x) / ball.vx
                let futureY = ball.y + ball.vy * arrival
                if arrival > 0 && arrival < 0.42 && abs(futureY - p.y) < 2.8 {
                    players[p.id].action = FootballAction(kind: .dive, direction: FootballVector(x: 0, y: futureY < p.y ? -1 : 1))
                }
            }
            let diving = players[p.id].action?.kind == .dive
            let travel = ball.position - old.position
            let t = min(1, max(0, (p.position - old.position).dot(travel) / max(0.00001, travel.dot(travel))))
            let distance = (old.position + travel * t - p.position).length
            guard distance < (diving ? 1.5 : 0.85), ball.z < (diving ? 2.25 : 1.9) else { continue }
            if ball.velocity.length < 19 && distance < (diving ? 1.15 : 0.85) {
                carrierID = p.id; ball.carrier = p.side; ball.heldBy = p.id; ball.heldFor = 0
                receiverID = nil; receiveAssist = 0; lastTouch = p.side; select(p.id, side: p.side)
                positionHeldBall()
            } else {
                ball.vx = p.side.sign * max(6, abs(ball.vx) * 0.5)
                ball.vy += ball.y < p.y ? -3 : 3; ball.vz = 2
                releaseBall(delay: 0.35); lastTouch = p.side
                if !diving { players[p.id].action = FootballAction(kind: .dive, direction: FootballVector(x: 0, y: ball.y < p.y ? -1 : 1)) }
            }
            return
        }
    }
    private mutating func resolveBoundary(from old: FootballBall) -> Bool {
        let r = FootballPitch.ballRadius
        if ball.x < -r || ball.x > 105 + r {
            let atLeft = ball.x < 0, plane = ball.x < 0 ? -r : 105 + r
            let t = min(1, max(0, (plane - old.x) / (ball.x - old.x)))
            let y = old.y + (ball.y - old.y) * t, z = old.z + (ball.z - old.z) * t
            if abs(y - 34) + r < 3.66 && z + r < 2.44 {
                if atLeft { rightScore += 1 } else { leftScore += 1 }
                resetPositions(conceding: atLeft ? .left : .right)
            } else {
                let defender: ElevenSide = atLeft ? .left : .right
                let corner = lastTouch == defender
                restart(at: FootballVector(x: corner ? (atLeft ? 0.2 : 104.8) : (atLeft ? 5.5 : 99.5),
                                           y: corner ? (ball.y < 34 ? 0.3 : 67.7) : 34),
                        owner: corner ? defender.opposite : defender, label: corner ? "코너킥" : "골킥")
            }
            return true
        }
        if ball.y < -r || ball.y > 68 + r {
            if ball.throwGrace > 0 && ((ball.y < 0 && ball.vy > 0) || (ball.y > 68 && ball.vy < 0)) { return false }
            let near = ball.y > 68
            restart(at: FootballVector(x: min(104, max(1, ball.x)), y: near ? 68.65 : -0.65),
                    owner: lastTouch.opposite, label: "스로인 · S/A로 던지기")
            if let id = carrierID {
                players[id].facingX = 0; players[id].facingY = near ? -1 : 1
                ball.heldBy = id; ball.throwIn = true; positionHeldBall()
            }
            return true
        }
        return false
    }
    private mutating func receiveBall() {
        guard carrierID == nil, ball.recatchDelay == 0, ball.z < 0.5 else { return }
        guard let p = players.filter({ $0.fallenFor == 0 && $0.action == nil })
            .min(by: { ($0.position - ball.position).length < ($1.position - ball.position).length }),
              (p.position - ball.position).length < 0.86 else { return }
        if (ball.velocity - p.velocity).length > 12 {
            ball.vx *= 0.42; ball.vy *= 0.42; ball.recatchDelay = 0.12; lastTouch = p.side; return
        }
        carrierID = p.id; ball.carrier = p.side; lastTouch = p.side
        receiverID = nil; receiveAssist = 0
        players[p.id].touchCooldown = 0
        select(p.id, side: p.side)
    }
    private func aiTargets() -> [Int: FootballVector] {
        var result: [Int: FootballVector] = [:]
        for side in [ElevenSide.left, .right] {
            let chaser = players.filter { $0.side == side && !$0.goalkeeper && !isHuman($0.id) && $0.fallenFor == 0 }
                .min { ($0.position - ball.position).length < ($1.position - ball.position).length }?.id
            for p in players where p.side == side && !isHuman(p.id) {
                var target: FootballVector
                if p.goalkeeper {
                    let goalX = side == .left ? 2.0 : 103.0
                    let arrival = abs(ball.vx) > 0.1 ? (goalX - ball.x) / ball.vx : -1
                    let predictedY = arrival > 0 && arrival < 2 ? ball.y + ball.vy * arrival : ball.y
                    target = FootballVector(x: goalX, y: min(37.4, max(30.6, 34 + (predictedY - 34) * 0.8)))
                } else if carrierID == p.id {
                    target = FootballVector(x: side == .left ? 101 : 4, y: p.y + (34 - p.y) * 0.3)
                } else if ball.carrier != side && p.id == chaser {
                    target = ball.position + ball.velocity * 0.18
                } else {
                    target = FootballVector(x: p.homeX + (ball.x - 52.5) * 0.42 + (ball.carrier == side ? side.sign * 6 : 0),
                                            y: p.homeY + (ball.y - 34) * 0.18)
                }
                result[p.id] = FootballVector(x: min(102, max(3, target.x)), y: min(65, max(3, target.y)))
            }
        }
        return result
    }
    private func isHuman(_ id: Int) -> Bool { id == selectedID || (remoteControlled && id == rightSelectedID) }
    private mutating func chooseAIActions() {
        if let owner = carrierID, !isHuman(owner), canAct(owner) {
            let p = players[owner]
            if (p.side == .left ? 105 - p.x : p.x) < 24 { beginShot(owner) }
            else if players.contains(where: { $0.side != p.side && ($0.position - p.position).length < 3 }) {
                beginPass(owner)
            }
        }
        if let owner = carrierID {
            for p in players where p.side != players[owner].side && !isHuman(p.id) && !p.goalkeeper {
                if canAct(p.id), (p.position - ball.position).length < 1.35,
                   p.facing.dot((ball.position - p.position).unit) > 0.65 {
                    players[p.id].action = FootballAction(kind: .standing, direction: p.facing)
                }
            }
        }
    }
    private mutating func restart(at position: FootballVector, owner: ElevenSide, label: String) {
        receiverID = nil; receiveAssist = 0
        guard let taker = players.filter({ $0.side == owner }).min(by: {
            ($0.position - position).length < ($1.position - position).length
        })?.id else { return }
        for i in players.indices {
            players[i].vx = 0; players[i].vy = 0; players[i].action = nil
            if i != taker && (players[i].position - position).length < 3 {
                let offset = (players[i].position - position).unit
                players[i].x = min(104, max(1, position.x + offset.x * 3))
                players[i].y = min(67, max(1, position.y + offset.y * 3))
            }
        }
        players[taker].x = min(104.65, max(0.35, position.x - owner.sign * 0.65))
        players[taker].y = position.y; players[taker].facingX = owner.sign; players[taker].facingY = 0
        players[taker].fallenFor = 0; players[taker].cooldown = 0; players[taker].touchCooldown = 0
        ball = FootballBall(x: position.x, y: position.y, carrier: owner)
        carrierID = taker; lastTouch = owner; select(taker, side: owner)
        kickoffFor = 1; restartLabel = label
    }
    private mutating func resetPositions(conceding side: ElevenSide) {
        receiverID = nil; receiveAssist = 0
        let formation: [(Double, Double)] = [
            (3, 34), (23, 10), (21, 26), (21, 42), (23, 58),
            (35, 18), (33, 34), (35, 50), (45, 13), (43, 34), (45, 55)
        ]
        players = [ElevenSide.left, .right].flatMap { team in
            formation.enumerated().map { number, home in
                let x = team == .left ? home.0 : 105 - home.0
                return ElevenPlayer(id: (team == .left ? 0 : 11) + number, side: team,
                                    homeX: x, homeY: home.1, goalkeeper: number == 0,
                                    x: x, y: home.1, facingX: team.sign, facingY: 0)
            }
        }
        let id = side == .left ? 9 : 20
        players[id].x = side == .left ? 51.8 : 53.2
        ball = FootballBall(carrier: side); carrierID = id; lastTouch = side
        selectedID = 9; rightSelectedID = 20
        kickoffFor = 1.3; restartLabel = "킥오프"
    }
    private mutating func synchronizePresentation() { previousPlayers = players; previousBall = ball }
}
