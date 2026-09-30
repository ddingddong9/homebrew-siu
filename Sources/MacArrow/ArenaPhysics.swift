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
    var lastCarryPosition: CGPoint?
    var dribblePhase: Double = 0

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
                if ball.z <= 0 {
                    ball.z = 0
                    // Small diminishing rebounds instead of snapping to the turf.
                    ball.vz = ball.vz < -0.18 ? -ball.vz * 0.32 : 0
                    ball.vx *= 0.88; ball.vy *= 0.88
                }
            }
            ball.recatchDelay = max(0, ball.recatchDelay - dt)
            let drag = pow(ball.z > 0 ? 0.998 : 0.985, dt * 60)
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
                     power: Double = 1, aimToward goal: FieldEdge? = nil) -> Bool {
        guard ball.z < 0.03, hypot(ball.x - player.x, ball.y - player.y) < 0.075 else { return false }
        let length = hypot(direction.x, direction.y)
        guard length > 0.01 else { return false }
        let speed = 1.1 * min(max(power, 0.2), 1.5)
        let inputX = direction.x / length
        let inputY = direction.y / length
        let target = goal.map { goalDirection(for: ball, toward: $0) }
        let weight = target == nil ? 0 : 0.28
        let aimedX = inputX * (1 - weight) + (target?.x ?? 0) * weight
        let aimedY = inputY * (1 - weight) + (target?.y ?? 0) * weight
        let aimedLength = hypot(aimedX, aimedY)
        ball.vx = aimedX / aimedLength * speed
        ball.vy = aimedY / aimedLength * speed
        ball.carrier = nil
        ball.z = 0; ball.vz = 0; ball.curve = 0; ball.recatchDelay = 0.18
        return true
    }

    static func curveKick(_ ball: inout ArenaBall, from player: CGPoint,
                          direction: CGPoint, toward goal: FieldEdge) -> Bool {
        let target = goalDirection(for: ball, toward: goal)
        let inward = ball.y < 0.5 ? 1.0 : (ball.y > 0.5 ? -1.0 : (direction.y >= 0 ? 1.0 : -1.0))
        let bend = inward * (goal == .right ? 1.0 : -1.0)
        let targetAngle = atan2(target.y, target.x)
        let launchAngle = targetAngle - bend * 0.16
        guard kick(&ball, from: player,
                   direction: CGPoint(x: cos(launchAngle), y: sin(launchAngle))) else { return false }
        ball.curve = bend * 1.2
        ball.recatchDelay = 0.28
        return true
    }

    private static func goalDirection(for ball: ArenaBall, toward goal: FieldEdge) -> CGPoint {
        let dx = (goal == .right ? 0.98 : 0.02) - ball.x
        let dy = 0.5 - ball.y
        let length = max(hypot(dx, dy), 0.001)
        return CGPoint(x: dx / length, y: dy / length)
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

    static func backheel(_ ball: inout ArenaBall, from player: CGPoint, direction: CGPoint) -> Bool {
        guard kick(&ball, from: player, direction: CGPoint(x: -direction.x, y: -direction.y), power: 0.85) else { return false }
        ball.z = 0.006
        ball.vz = 0.12
        ball.recatchDelay = 0.32
        return true
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
        ball.lastCarryPosition = player
        ball.dribblePhase = 0
        ball.vx = 0
        ball.vy = 0
        ball.z = 0; ball.vz = 0; ball.curve = 0
        return true
    }

    static func carry(_ ball: inout ArenaBall, beside player: CGPoint, direction: CGPoint,
                      turnProgress: Double? = nil, stepoverProgress: Double? = nil) {
        guard ball.carrier != nil else { return }
        if let previous = ball.lastCarryPosition {
            let distance = hypot(player.x - previous.x, player.y - previous.y)
            if distance < 0.1 { ball.dribblePhase = (ball.dribblePhase + distance * 150).truncatingRemainder(dividingBy: 2 * .pi) }
        }
        ball.lastCarryPosition = player
        let angle = atan2(direction.y, direction.x) + (turnProgress.map { 2 * .pi * $0 } ?? 0)
        let reach = 0.039 + 0.012 * (1 - cos(ball.dribblePhase)) / 2
        let lateral = 0.010 + 0.004 * sin(ball.dribblePhase) + (stepoverProgress.map { sin($0 * .pi * 6) * 0.017 } ?? 0)
        ball.x = min(max(player.x + cos(angle) * reach - sin(angle) * lateral, 0.04), 0.98)
        ball.y = min(max(player.y + sin(angle) * reach + cos(angle) * lateral, 0.08), 0.92)
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
        guard ball.recatchDelay <= 0, ball.z < 0.02, distance < 0.038 else { return false }
        let angle = distance > 0.001 ? atan2(dy, dx) : atan2(direction.y, direction.x)
        ball.x = min(max(player.x + cos(angle) * 0.038, 0.04), 0.96)
        ball.y = min(max(player.y + sin(angle) * 0.038, 0.08), 0.92)
        ball.vx = cos(angle) * max(abs(ball.vx), 0.16)
        ball.vy = sin(angle) * max(abs(ball.vy), 0.16)
        return true
    }
}
