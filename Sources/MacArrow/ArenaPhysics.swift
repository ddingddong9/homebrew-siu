import Foundation

struct ArenaBall {
    var x: Double = 0.5
    var y: Double = 0.5
    var vx: Double = 0
    var vy: Double = 0

    static let kickoff = ArenaBall()
}

enum ArenaStepResult: Equatable {
    case inPlay
    case goalAtLeft
    case goalAtRight
}

enum ArenaPhysics {
    static func step(_ ball: inout ArenaBall, dt rawDelta: TimeInterval) -> ArenaStepResult {
        let dt = min(max(rawDelta, 0), 0.05)
        ball.x += ball.vx * dt
        ball.y += ball.vy * dt
        let drag = pow(0.985, dt * 60)
        ball.vx *= drag
        ball.vy *= drag

        if ball.y < 0.08 {
            ball.y = 0.08
            ball.vy = abs(ball.vy) * 0.68
        } else if ball.y > 0.92 {
            ball.y = 0.92
            ball.vy = -abs(ball.vy) * 0.68
        }
        if ball.x < 0.04 {
            if (0.38...0.62).contains(ball.y) { return .goalAtLeft }
            ball.x = 0.04
            ball.vx = abs(ball.vx) * 0.68
        } else if ball.x > 0.96 {
            if (0.38...0.62).contains(ball.y) { return .goalAtRight }
            ball.x = 0.96
            ball.vx = -abs(ball.vx) * 0.68
        }
        if hypot(ball.vx, ball.vy) < 0.008 { ball.vx = 0; ball.vy = 0 }
        return .inPlay
    }

    static func kick(_ ball: inout ArenaBall, from player: CGPoint, direction: CGPoint,
                     power: Double = 1) -> Bool {
        guard hypot(ball.x - player.x, ball.y - player.y) < 0.075 else { return false }
        let length = hypot(direction.x, direction.y)
        guard length > 0.01 else { return false }
        let speed = 1.1 * min(max(power, 0.2), 1.5)
        ball.vx = direction.x / length * speed
        ball.vy = direction.y / length * speed
        return true
    }

    static func tackle(_ ball: inout ArenaBall, from player: CGPoint, direction: CGPoint) -> Bool {
        kick(&ball, from: player, direction: direction, power: 0.55)
    }

    static func contact(_ ball: inout ArenaBall, player: CGPoint, direction: CGPoint) {
        let dx = ball.x - player.x
        let dy = ball.y - player.y
        let distance = hypot(dx, dy)
        guard distance < 0.038 else { return }
        let angle = distance > 0.001 ? atan2(dy, dx) : atan2(direction.y, direction.x)
        ball.x = min(max(player.x + cos(angle) * 0.038, 0.04), 0.96)
        ball.y = min(max(player.y + sin(angle) * 0.038, 0.08), 0.92)
        ball.vx = cos(angle) * max(abs(ball.vx), 0.16)
        ball.vy = sin(angle) * max(abs(ball.vy), 0.16)
    }
}
