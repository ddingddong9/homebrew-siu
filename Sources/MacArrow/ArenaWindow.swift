import AppKit

@MainActor
final class ArenaWindowController: NSWindowController, NSWindowDelegate {
    var onKick: ((CGPoint, CGPoint) -> Void)?
    var onTackle: ((CGPoint, CGPoint) -> Void)?
    var onClose: (() -> Void)?
    private let arenaView: ArenaView

    init() {
        let size = NSSize(width: 1060, height: 690)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SIU — 1대1 축구"
        window.minSize = NSSize(width: 760, height: 500)
        window.center()
        let view = ArenaView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        arenaView = view
        super.init(window: window)
        window.delegate = self
        view.onKick = { [weak self] position, direction in self?.onKick?(position, direction) }
        view.onTackle = { [weak self] position, direction in self?.onTackle?(position, direction) }
    }

    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false
    }

    func show(homeSide: FieldEdge) {
        arenaView.reset(homeSide: homeSide)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(arenaView)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func hide() { window?.orderOut(nil) }
    func advance(dt: TimeInterval) { arenaView.advance(dt: dt) }
    var localPosition: CGPoint { arenaView.localPosition }
    var localDirection: CGPoint { arenaView.localDirection }
    var remotePosition: CGPoint { arenaView.remotePosition }
    func stun() { arenaView.stun() }
    func animateRemoteKick() { arenaView.remoteKickAt = ProcessInfo.processInfo.systemUptime }
    func animateRemoteTackle() { arenaView.remoteTackleAt = ProcessInfo.processInfo.systemUptime }
    func showFeedback(_ message: String) { arenaView.showFeedback(message) }
    func setRemote(position: CGPoint, direction: CGPoint) {
        arenaView.remoteTarget = position
        arenaView.remoteDirection = direction
        arenaView.needsDisplay = true
    }
    func render(ball: ArenaBall, myScore: Int, theirScore: Int,
                remaining: TimeInterval, status: String) {
        arenaView.ball = ball
        arenaView.myScore = myScore
        arenaView.theirScore = theirScore
        arenaView.remaining = remaining
        arenaView.status = status
        arenaView.needsDisplay = true
    }
}

@MainActor
private final class ArenaView: NSView {
    var onKick: ((CGPoint, CGPoint) -> Void)?
    var onTackle: ((CGPoint, CGPoint) -> Void)?
    var localPosition = CGPoint(x: 0.25, y: 0.5)
    var remotePosition = CGPoint(x: 0.75, y: 0.5)
    var remoteTarget = CGPoint(x: 0.75, y: 0.5)
    var remoteDirection = CGPoint(x: -1, y: 0)
    var ball = ArenaBall.kickoff
    var myScore = 0
    var theirScore = 0
    var remaining: TimeInterval = 0
    var status = ""
    var remoteKickAt: TimeInterval = -.infinity
    var remoteTackleAt: TimeInterval = -.infinity
    private(set) var localDirection = CGPoint(x: 1, y: 0)
    private var velocity = CGPoint.zero
    private var stunnedUntil: TimeInterval = 0
    private var homeSide: FieldEdge = .left
    private var keys = Set<UInt16>()
    private var sprint = false
    private var animationPhase = 0.0
    private var kickAt: TimeInterval = -.infinity
    private var tackleAt: TimeInterval = -.infinity
    private var feedback = ""
    private var feedbackUntil: TimeInterval = 0
    private let sprites: [NSImage] = (1...4).compactMap { index in
        guard let url = ResourceBundle.images.url(forResource: String(format: "move-%02d", index), withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    private let kickSprites: [NSImage] = (1...4).compactMap { index in
        guard let url = ResourceBundle.images.url(forResource: String(format: "kick-side-%02d", index), withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    private let tackleSprites: [NSImage] = (1...4).compactMap { index in
        guard let url = ResourceBundle.images.url(forResource: String(format: "tackle-%02d", index), withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    override var acceptsFirstResponder: Bool { true }

    func reset(homeSide: FieldEdge) {
        self.homeSide = homeSide
        localPosition = CGPoint(x: homeSide == .left ? 0.25 : 0.75, y: 0.5)
        remotePosition = CGPoint(x: homeSide == .left ? 0.75 : 0.25, y: 0.5)
        remoteTarget = remotePosition
        localDirection = CGPoint(x: homeSide == .left ? 1 : -1, y: 0)
        remoteDirection = CGPoint(x: -localDirection.x, y: 0)
        velocity = .zero
        stunnedUntil = 0
        kickAt = -.infinity
        tackleAt = -.infinity
        remoteKickAt = -.infinity
        remoteTackleAt = -.infinity
        keys.removeAll()
        needsDisplay = true
    }

    func showFeedback(_ message: String) {
        feedback = message
        feedbackUntil = ProcessInfo.processInfo.systemUptime + 1.2
        needsDisplay = true
    }

    func stun() {
        stunnedUntil = ProcessInfo.processInfo.systemUptime + 0.5
        velocity = .zero
        keys.removeAll()
    }

    func advance(dt rawDelta: TimeInterval) {
        let dt = min(max(rawDelta, 0), 0.05)
        if window?.isKeyWindow != true || ProcessInfo.processInfo.systemUptime < stunnedUntil {
            keys.removeAll(); sprint = false
        }
        let dx = CGFloat((keys.contains(124) ? 1 : 0) - (keys.contains(123) ? 1 : 0))
        let dy = CGFloat((keys.contains(126) ? 1 : 0) - (keys.contains(125) ? 1 : 0))
        let length = hypot(dx, dy)
        let speed: CGFloat = sprint ? 0.48 : 0.33
        let target = length > 0 ? CGPoint(x: dx / length * speed, y: dy / length * speed) : .zero
        let blend = min(CGFloat(1), CGFloat(dt) * 14)
        velocity.x += (target.x - velocity.x) * blend
        velocity.y += (target.y - velocity.y) * blend
        localPosition.x = min(max(localPosition.x + velocity.x * dt, 0.065), 0.935)
        localPosition.y = min(max(localPosition.y + velocity.y * dt, 0.10), 0.90)
        let remoteBlend = min(CGFloat(1), CGFloat(dt) * 12)
        remotePosition.x += (remoteTarget.x - remotePosition.x) * remoteBlend
        remotePosition.y += (remoteTarget.y - remotePosition.y) * remoteBlend
        if length > 0 {
            let current = atan2(localDirection.y, localDirection.x)
            let wanted = atan2(dy, dx)
            let delta = atan2(sin(wanted - current), cos(wanted - current))
            let step = min(max(delta, -CGFloat(dt) * 9), CGFloat(dt) * 9)
            localDirection = CGPoint(x: cos(current + step), y: sin(current + step))
        }
        if hypot(velocity.x, velocity.y) > 0.02 { animationPhase += dt * (sprint ? 11 : 8) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124, 125, 126: keys.insert(event.keyCode)
        case 49: if !event.isARepeat {
            kickAt = ProcessInfo.processInfo.systemUptime
            onKick?(localPosition, localDirection)
        }
        case 0: if !event.isARepeat {
            tackleAt = ProcessInfo.processInfo.systemUptime
            onTackle?(localPosition, localDirection)
        }
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if keys.contains(event.keyCode) { keys.remove(event.keyCode) }
        else { super.keyUp(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        sprint = event.modifierFlags.contains(.shift)
        super.flagsChanged(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawPitch()
        drawGoals()
        drawPlayer(at: remotePosition, direction: remoteDirection, isLocal: false)
        drawPlayer(at: localPosition, direction: localDirection, isLocal: true)
        drawBall()
        drawScoreboard()
        drawControls()
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: bounds.width * x, y: bounds.height * y)
    }

    private func drawPitch() {
        NSColor(calibratedRed: 0.035, green: 0.18, blue: 0.11, alpha: 1).setFill()
        bounds.fill()
        let field = NSRect(x: bounds.width * 0.04, y: bounds.height * 0.08,
                           width: bounds.width * 0.92, height: bounds.height * 0.84)
        NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.24, alpha: 1).setFill()
        field.fill()
        for stripe in 0..<10 where stripe.isMultiple(of: 2) {
            NSColor.white.withAlphaComponent(0.045).setFill()
            NSRect(x: field.minX + field.width * CGFloat(stripe) / 10, y: field.minY,
                   width: field.width / 10, height: field.height).fill()
        }
        NSColor.white.withAlphaComponent(0.86).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 2.5
        lines.appendRect(field)
        lines.move(to: point(0.5, 0.08)); lines.line(to: point(0.5, 0.92))
        lines.appendOval(in: NSRect(x: bounds.midX - 65, y: bounds.midY - 65, width: 130, height: 130))
        lines.appendRect(NSRect(x: field.minX, y: bounds.height * 0.27,
                                width: field.width * 0.15, height: bounds.height * 0.46))
        lines.appendRect(NSRect(x: field.maxX - field.width * 0.15, y: bounds.height * 0.27,
                                width: field.width * 0.15, height: bounds.height * 0.46))
        lines.appendRect(NSRect(x: field.minX, y: bounds.height * 0.38,
                                width: field.width * 0.055, height: bounds.height * 0.24))
        lines.appendRect(NSRect(x: field.maxX - field.width * 0.055, y: bounds.height * 0.38,
                                width: field.width * 0.055, height: bounds.height * 0.24))
        lines.stroke()
        for x in [CGFloat(0.2), 0.5, 0.8] {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.width * x - 3, y: bounds.midY - 3,
                                        width: 6, height: 6)).fill()
        }
    }

    private func drawGoals() {
        for x in [CGFloat(0.015), 0.96] {
            let rect = NSRect(x: bounds.width * x, y: bounds.height * 0.38,
                              width: bounds.width * 0.025, height: bounds.height * 0.24)
            NSColor.white.withAlphaComponent(0.18).setFill()
            rect.fill()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 3
            outline.stroke()
        }
    }

    private func drawPlayer(at position: CGPoint, direction: CGPoint, isLocal: Bool) {
        let center = point(position.x, position.y)
        let color = isLocal ? NSColor.systemYellow : NSColor.systemCyan
        let marker = NSBezierPath(ovalIn: NSRect(x: center.x - 32, y: center.y - 20, width: 64, height: 30))
        color.withAlphaComponent(0.27).setFill(); marker.fill()
        marker.lineWidth = 3; color.setStroke(); marker.stroke()
        if !sprites.isEmpty {
            let now = ProcessInfo.processInfo.systemUptime
            let sinceKick = now - (isLocal ? kickAt : remoteKickAt)
            let sinceTackle = now - (isLocal ? tackleAt : remoteTackleAt)
            let image: NSImage
            if sinceKick < 0.55, !kickSprites.isEmpty {
                image = kickSprites[min(kickSprites.count - 1, Int(sinceKick / 0.14))]
            } else if sinceTackle < 0.50, !tackleSprites.isEmpty {
                image = tackleSprites[min(tackleSprites.count - 1, Int(sinceTackle / 0.13))]
            } else {
                let frame = isLocal ? Int(animationPhase) % sprites.count : 2
                image = sprites[frame]
            }
            let height: CGFloat = 118
            let width = min(88, height * image.size.width / max(image.size.height, 1))
            let rect = NSRect(x: center.x - width / 2, y: center.y - 12, width: width, height: height)
            if direction.x < -0.1 {
                guard let context = NSGraphicsContext.current?.cgContext else { return }
                context.saveGState()
                context.translateBy(x: bounds.width, y: 0)
                context.scaleBy(x: -1, y: 1)
                image.draw(in: NSRect(x: bounds.width - rect.maxX, y: rect.minY,
                                      width: rect.width, height: rect.height))
                context.restoreGState()
            } else { image.draw(in: rect) }
        }
        let arrowTip = point(position.x + direction.x * 0.035, position.y + direction.y * 0.052)
        let arrow = NSBezierPath()
        arrow.move(to: center); arrow.line(to: arrowTip)
        arrow.lineWidth = 5; color.setStroke(); arrow.stroke()
        let label = isLocal ? "나" : "상대"
        NSString(string: label).draw(in: NSRect(x: center.x - 25, y: center.y - 48, width: 50, height: 20),
                                      withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14),
                                                       .foregroundColor: NSColor.white,
                                                       .paragraphStyle: centeredText])
    }

    private var centeredText: NSParagraphStyle {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        return style
    }

    private func drawBall() {
        let center = point(ball.x, ball.y)
        let shadow = NSBezierPath(ovalIn: NSRect(x: center.x - 18, y: center.y - 15, width: 36, height: 14))
        NSColor.black.withAlphaComponent(0.38).setFill(); shadow.fill()
        NSString(string: "⚽️").draw(in: NSRect(x: center.x - 22, y: center.y - 16, width: 44, height: 44),
                                   withAttributes: [.font: NSFont.systemFont(ofSize: 34)])
    }

    private func drawScoreboard() {
        let minutes = Int(max(0, remaining)) / 60
        let seconds = Int(max(0, remaining)) % 60
        let title = "나  \(myScore)  :  \(theirScore)  상대     \(String(format: "%02d:%02d", minutes, seconds))"
        let board = NSRect(x: bounds.midX - 210, y: bounds.maxY - 60, width: 420, height: 48)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: board, xRadius: 12, yRadius: 12).fill()
        NSString(string: title).draw(in: board.insetBy(dx: 10, dy: 8), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 21, weight: .bold),
            .foregroundColor: NSColor.white, .paragraphStyle: centeredText
        ])
        let notice = !status.isEmpty ? status :
            (ProcessInfo.processInfo.systemUptime < feedbackUntil ? feedback : "")
        if !notice.isEmpty {
            NSString(string: notice).draw(in: NSRect(x: bounds.midX - 240, y: bounds.midY + 125,
                                                     width: 480, height: 54), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 34), .foregroundColor: NSColor.white,
                .paragraphStyle: centeredText
            ])
        }
    }

    private func drawControls() {
        NSString(string: "방향키 이동·방향  ·  Shift 달리기  ·  Space 슛  ·  A 태클").draw(
            in: NSRect(x: 0, y: 9, width: bounds.width, height: 20),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                             .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                             .paragraphStyle: centeredText])
    }
}
