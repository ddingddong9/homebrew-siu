import Foundation

/// Shared by 1v1 local players and the authoritative 2v2 engine.
struct AthleteMotion {
    static let slideDuration = 0.55
    private(set) var stamina = 100.0
    private(set) var exhausted = false
    private(set) var slideRemaining = 0.0
    private(set) var cooldown = 0.0
    private var slideDirection = CGPoint.zero
    var isSliding: Bool { slideRemaining > 0 }
    mutating func startSlide(direction: CGPoint) -> Bool {
        let length = hypot(direction.x,direction.y)
        guard cooldown <= 0, length > 0.01 else { return false }
        slideDirection = CGPoint(x:direction.x/length,y:direction.y/length)
        slideRemaining = Self.slideDuration; cooldown = 1.15; return true
    }
    mutating func cancelSlide() { slideRemaining = 0 }
    mutating func tick(dt: Double, moving: Bool, sprint: Bool, canMove: Bool = true) -> (sprinting: Bool, slide: CGPoint?) {
        let dt = min(max(dt,0),0.05)
        cooldown = max(0,cooldown-dt)
        if !canMove { cancelSlide() }
        let sliding = isSliding
        if exhausted && stamina >= 20 { exhausted = false }
        let running = canMove && moving && sprint && !sliding && !exhausted && stamina > 0
        stamina = min(100,max(0,stamina + (running ? -24 : 15)*dt))
        if stamina <= 0 { exhausted = true }
        var velocity: CGPoint?
        if sliding {
            let speed = 0.16 + 0.8 * slideRemaining/Self.slideDuration
            velocity = CGPoint(x:slideDirection.x*speed,y:slideDirection.y*speed)
            slideRemaining = max(0,slideRemaining-dt)
        }
        return (running,velocity)
    }
}

enum SlidingContact {
    static func closest(to point:CGPoint,from start:CGPoint,to end:CGPoint) -> CGPoint {
        let dx = end.x-start.x, dy = end.y-start.y, squared = dx*dx+dy*dy
        let t = squared > 0 ? min(1,max(0,((point.x-start.x)*dx+(point.y-start.y)*dy)/squared)) : 0
        return CGPoint(x:start.x+dx*t,y:start.y+dy*t)
    }
}
