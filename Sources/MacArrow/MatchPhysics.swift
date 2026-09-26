import Foundation

enum FieldEdge { case left, right }

struct MatchBall {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double

    static let kickoff = MatchBall(x: 0.5, y: 0.12, vx: 0, vy: 0)
}

enum BallStepResult {
    case inPlay
    case transferred(y: Double, vx: Double, vy: Double)
    case ownGoal
}

enum MatchPhysics {
    static func step(_ ball: inout MatchBall, dt rawDelta: TimeInterval, ownGoal: FieldEdge) -> BallStepResult {
        let dt = min(max(rawDelta, 0), 0.05)
        ball.vy -= 0.9 * dt
        ball.x += ball.vx * dt
        ball.y += ball.vy * dt
        let drag = pow(0.992, dt * 60)
        ball.vx *= drag
        ball.vy *= drag

        if ball.y < 0.10 {
            ball.y = 0.10
            ball.vy = abs(ball.vy) < 0.055 ? 0 : -ball.vy * 0.58
            ball.vx *= 0.94
            if abs(ball.vx) < 0.012 { ball.vx = 0 }
        } else if ball.y > 0.95 {
            ball.y = 0.95
            ball.vy = -abs(ball.vy) * 0.6
        }

        let crossed: FieldEdge?
        if ball.x < 0.02 { crossed = .left }
        else if ball.x > 0.98 { crossed = .right }
        else { crossed = nil }
        guard let crossed else { return .inPlay }
        if crossed == ownGoal {
            if (0.10...0.42).contains(ball.y) { return .ownGoal }
            ball.x = crossed == .left ? 0.02 : 0.98
            ball.vx *= -0.65
            return .inPlay
        }
        return .transferred(y: ball.y, vx: ball.vx, vy: ball.vy)
    }

    static func kick(_ ball: inout MatchBall, dx: Double, dy: Double) {
        let length = max(hypot(dx, dy), 0.001)
        ball.vx = dx / length * 1.55
        ball.vy = dy / length * 1.15 + 0.44
    }

    static func tackle(_ ball: inout MatchBall, dx: Double, dy: Double) {
        let length = max(hypot(dx, dy), 0.001)
        ball.vx = dx / length * 0.95
        ball.vy = dy / length * 0.65 + 0.22
    }
}
