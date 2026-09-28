import Foundation

struct ArenaBall {
    var x: Double = 0.5
    var y: Double = 0.5
    var vx: Double = 0
    var vy: Double = 0
    var carrier: FieldEdge?
    var z: Double = 0
    var vz: Double = 0
    var curve: Double = 0
    var recatchDelay: Double = 0

    static let kickoff = ArenaBall()
}

enum ArenaStepResult: Equatable {
    case inPlay
    case goalAtLeft
    case goalAtRight
}

enum ArenaPhysics {
    static func startingX(conceding side: FieldEdge) -> (left: CGFloat, right: CGFloat) {
        side == .left ? (0.46, 0.75) : (0.25, 0.54)
    }

    static func mayTakeKickoff(owner: FieldEdge?, player: FieldEdge) -> Bool {
        owner == nil || owner == player
    }

    static func step(_ ball: inout ArenaBall, dt rawDelta: TimeInterval) -> ArenaStepResult {
        let dt = min(max(rawDelta, 0), 0.05)
        if ball.carrier == nil {
            if ball.curve != 0 {
                let angle = ball.curve * dt
                let vx = ball.vx * cos(angle) - ball.vy * sin(angle)
                ball.vy = ball.vx * sin(angle) + ball.vy * cos(angle)
                ball.vx = vx
                ball.curve *= pow(0.96, dt * 60)
                if abs(ball.curve) < 0.02 { ball.curve = 0 }
            }
            ball.x += ball.vx * dt
            ball.y += ball.vy * dt
            if ball.z > 0 || ball.vz > 0 {
                ball.z += ball.vz * dt
                ball.vz -= 1.4 * dt
                if ball.z <= 0 { ball.z = 0; ball.vz = 0 }
            }
            ball.recatchDelay = max(0, ball.recatchDelay - dt)
            let drag = pow(0.985, dt * 60)
            ball.vx *= drag
            ball.vy *= drag
        }

        if ball.y < 0.08 {
            ball.y = 0.08
            ball.vy = abs(ball.vy) * 0.68
        } else if ball.y > 0.92 {
            ball.y = 0.92
            ball.vy = -abs(ball.vy) * 0.68
        }
        if ball.x < 0.04 {
            if (0.38...0.62).contains(ball.y) && ball.z < 0.14 { return .goalAtLeft }
            ball.x = 0.04
            ball.vx = abs(ball.vx) * 0.68
        } else if ball.x > 0.96 {
            if (0.38...0.62).contains(ball.y) && ball.z < 0.14 { return .goalAtRight }
            ball.x = 0.96
            ball.vx = -abs(ball.vx) * 0.68
        }
        if hypot(ball.vx, ball.vy) < 0.008 { ball.vx = 0; ball.vy = 0 }
        return .inPlay
    }

    static func kick(_ ball: inout ArenaBall, from player: CGPoint, direction: CGPoint,
                     power: Double = 1) -> Bool {
        guard ball.z < 0.03, hypot(ball.x - player.x, ball.y - player.y) < 0.075 else { return false }
        let length = hypot(direction.x, direction.y)
        guard length > 0.01 else { return false }
        let speed = 1.1 * min(max(power, 0.2), 1.5)
        ball.vx = direction.x / length * speed
        ball.vy = direction.y / length * speed
        ball.carrier = nil
        ball.z = 0; ball.vz = 0; ball.curve = 0; ball.recatchDelay = 0.18
        return true
    }

    static func curveKick(_ ball: inout ArenaBall, from player: CGPoint,
                          direction: CGPoint) -> Bool {
        guard kick(&ball, from: player, direction: direction) else { return false }
        let inward = ball.y < 0.5 ? 1.0 : -1.0
        ball.curve = inward * (direction.x >= 0 ? 1 : -1) * 1.8
        ball.recatchDelay = 0.28
        return true
    }

    static func rainbow(_ ball: inout ArenaBall, from player: CGPoint,
                        direction: CGPoint) -> Bool {
        guard ball.carrier != nil, hypot(ball.x - player.x, ball.y - player.y) < 0.075 else { return false }
        let length = hypot(direction.x, direction.y)
        guard length > 0.01 else { return false }
        ball.carrier = nil
        ball.vx = direction.x / length * 0.35
        ball.vy = direction.y / length * 0.35
        ball.z = 0.015
        ball.vz = 0.56
        ball.curve = 0
        ball.recatchDelay = 0.72
        return true
    }

    static func tackle(_ ball: inout ArenaBall, from player: CGPoint, direction: CGPoint) -> Bool {
        kick(&ball, from: player, direction: direction, power: 0.55)
    }

    static func powerKick(_ ball: inout ArenaBall, from player: CGPoint,
                          toward goal: FieldEdge) -> Bool {
        guard ball.z < 0.03, hypot(ball.x - player.x, ball.y - player.y) < 0.075 else { return false }
        let targetX = goal == .right ? 0.98 : 0.02
        let dx = targetX - ball.x
        let dy = 0.5 - ball.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return false }
        ball.vx = dx / length * 2.2
        ball.vy = dy / length * 2.2
        ball.carrier = nil
        ball.z = 0; ball.vz = 0; ball.curve = 0; ball.recatchDelay = 0.18
        return true
    }

    static func capture(_ ball: inout ArenaBall, by side: FieldEdge, player: CGPoint) -> Bool {
        guard ball.carrier == nil, ball.z < 0.02, ball.recatchDelay <= 0,
              hypot(ball.vx, ball.vy) < 0.7,
              hypot(ball.x - player.x, ball.y - player.y) < 0.064 else { return false }
        ball.carrier = side
        ball.vx = 0
        ball.vy = 0
        ball.z = 0; ball.vz = 0; ball.curve = 0
        return true
    }

    static func carry(_ ball: inout ArenaBall, beside player: CGPoint, direction: CGPoint,
                      turnProgress: Double? = nil) {
        guard ball.carrier != nil else { return }
        let angle = atan2(direction.y, direction.x) + (turnProgress.map { 2 * .pi * $0 } ?? 0)
        ball.x = min(max(player.x + cos(angle) * 0.046 - sin(angle) * 0.012, 0.04), 0.98)
        ball.y = min(max(player.y + sin(angle) * 0.046 + cos(angle) * 0.012, 0.08), 0.92)
        ball.vx = 0
        ball.vy = 0
        ball.z = 0; ball.vz = 0; ball.curve = 0
    }

    static func dispossess(_ ball: inout ArenaBall, direction: CGPoint) {
        ball.carrier = nil
        ball.vx = direction.x * 0.28
        ball.vy = direction.y * 0.28
        ball.recatchDelay = 0.2
    }

    @discardableResult
    static func contact(_ ball: inout ArenaBall, player: CGPoint, direction: CGPoint) -> Bool {
        let dx = ball.x - player.x
        let dy = ball.y - player.y
        let distance = hypot(dx, dy)
        guard ball.z < 0.02, distance < 0.038 else { return false }
        let angle = distance > 0.001 ? atan2(dy, dx) : atan2(direction.y, direction.x)
        ball.x = min(max(player.x + cos(angle) * 0.038, 0.04), 0.96)
        ball.y = min(max(player.y + sin(angle) * 0.038, 0.08), 0.92)
        ball.vx = cos(angle) * max(abs(ball.vx), 0.16)
        ball.vy = sin(angle) * max(abs(ball.vy), 0.16)
        return true
    }
}
