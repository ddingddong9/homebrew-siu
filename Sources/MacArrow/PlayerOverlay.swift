import AppKit

private enum PlayerDockSide {
    case left
    case right

    static func from(_ layout: ScreenLayout) -> PlayerDockSide {
        guard let local = layout.screens.first(where: \.isLocal) else { return .right }
        let peers = layout.screens.filter { !$0.isLocal }
        guard !peers.isEmpty else { return .right }
        let averagePeerX = peers.map(\.x).reduce(0, +) / Double(peers.count)
        return local.x >= averagePeerX ? .right : .left
    }
}

private enum PlayerHeading {
    case up, upRight, right, downRight, down, downLeft, left, upLeft

    init(dx: CGFloat, dy: CGFloat) {
        let ax = abs(dx), ay = abs(dy)
        if ax < ay * 0.414 { self = dy >= 0 ? .up : .down }
        else if ay < ax * 0.414 { self = dx >= 0 ? .right : .left }
        else if dx > 0 { self = dy > 0 ? .upRight : .downRight }
        else { self = dy > 0 ? .upLeft : .downLeft }
    }

    var isMirrored: Bool { [.left, .upLeft, .downLeft].contains(self) }
    var vector: CGPoint {
        switch self {
        case .up: return CGPoint(x: 0, y: 1)
        case .upRight: return CGPoint(x: 0.707, y: 0.707)
        case .right: return CGPoint(x: 1, y: 0)
        case .downRight: return CGPoint(x: 0.707, y: -0.707)
        case .down: return CGPoint(x: 0, y: -1)
        case .downLeft: return CGPoint(x: -0.707, y: -0.707)
        case .left: return CGPoint(x: -1, y: 0)
        case .upLeft: return CGPoint(x: -0.707, y: 0.707)
        }
    }
}

private final class GamePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PlayerWindowController: NSWindowController {
    var onKick: ((ShootDirection, Double, Double) -> Bool)?
    var onMatchKick: ((CGPoint, CGPoint) -> Bool)?
    var onMatchTackle: ((CGPoint, CGPoint) -> Void)?
    private let playerView: PlayerView
    private let ball = LocalBallWindowController()
    private var dockSide: PlayerDockSide
    private var facing: ShootDirection
    private var ballIsFlying = false
    private var matchMode = false

    init() {
        let dockSide = PlayerDockSide.from(ScreenLayoutStore.load())
        self.dockSide = dockSide
        self.facing = dockSide == .right ? .left : .right
        let size = NSSize(width: 270, height: 390)
        let panel = GamePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        let player = PlayerView(frame: NSRect(origin: .zero, size: size), facing: facing)
        self.playerView = player
        panel.contentView = player
        super.init(window: panel)
        player.onMove = { [weak self] dx, dy in self?.move(dx: dx, dy: dy) }
        player.onKickAttempt = { [weak self] in self?.tryKick() }
        player.onTackleAttempt = { [weak self] in self?.tryTackle() }
        positionAtConfiguredSide()
    }

    required init?(coder: NSCoder) { nil }

    func toggle() -> Bool {
        guard let window else { return false }
        if window.isVisible {
            window.orderOut(nil)
            ball.hide()
            return false
        }
        show()
        return true
    }

    func show() {
        refreshLayout()
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(playerView)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if !matchMode { resetBall() }
    }

    func setMatchMode(_ enabled: Bool) {
        matchMode = enabled
        if enabled { ball.hide() }
        else if window?.isVisible == true { resetBall() }
    }

    var footPosition: CGPoint? {
        guard let window else { return nil }
        return CGPoint(x: window.frame.midX, y: window.frame.minY + 42)
    }

    func stunForTackle() { playerView.stun() }

    func refreshLayout() {
        dockSide = PlayerDockSide.from(ScreenLayoutStore.load())
        facing = dockSide == .right ? .left : .right
        playerView.setFacing(facing)
        positionAtConfiguredSide()
        if window?.isVisible == true, !matchMode { resetBall() }
    }

    private func positionAtConfiguredSide() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let window else { return }
        let frame = screen.visibleFrame
        let x = dockSide == .right ? frame.maxX - window.frame.width - 12 : frame.minX + 12
        window.setFrameOrigin(NSPoint(x: x, y: frame.minY + 8))
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        var origin = window.frame.origin
        origin.x = min(max(origin.x + dx, bounds.minX), bounds.maxX - window.frame.width)
        origin.y = min(max(origin.y + dy, bounds.minY), bounds.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        if dx < 0 { facing = .left }
        if dx > 0 { facing = .right }
    }

    private func tryKick() {
        guard !playerView.isStunned else { return }
        if matchMode {
            guard let window else { return }
            let foot = CGPoint(x: window.frame.midX, y: window.frame.minY + 42)
            guard onMatchKick?(foot, playerView.aimVector) == true else {
                playerView.showTooFarFeedback()
                return
            }
            playerView.didKick()
            return
        }
        guard !ballIsFlying, let window else { return }
        let playerFoot = CGPoint(x: window.frame.midX, y: window.frame.minY + 42)
        let ballCenter = ball.center
        let distance = hypot(playerFoot.x - ballCenter.x, playerFoot.y - ballCenter.y)
        guard distance <= 125 else {
            playerView.showTooFarFeedback()
            return
        }
        let shotDirection: ShootDirection = abs(playerView.aimVector.x) < 0.1 ? facing :
            (playerView.aimVector.x < 0 ? .left : .right)
        guard onKick?(shotDirection, 0.16, 1) == true else { return }
        ballIsFlying = true
        playerView.didKick()
        ball.kick(direction: shotDirection) { [weak self] in
            guard let self else { return }
            self.ballIsFlying = false
            self.resetBall()
        }
    }

    private func tryTackle() {
        guard !playerView.isStunned else { return }
        guard playerView.didTackle(), !ballIsFlying, let window else { return }
        let playerFoot = CGPoint(x: window.frame.midX, y: window.frame.minY + 42)
        if matchMode {
            onMatchTackle?(playerFoot, playerView.aimVector)
            return
        }
        let ballCenter = ball.center
        guard hypot(playerFoot.x - ballCenter.x, playerFoot.y - ballCenter.y) < 135 else { return }
        ball.bump(along: playerView.aimVector)
    }

    private func resetBall() {
        guard let window else { return }
        let direction: CGFloat = facing == .left ? -1 : 1
        let point = CGPoint(
            x: window.frame.midX + direction * 105,
            y: window.frame.minY + 20
        )
        ball.show(centeredAt: point)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(playerView)
    }
}

@MainActor
private final class LocalBallWindowController {
    private let window: NSPanel
    var center: CGPoint { CGPoint(x: window.frame.midX, y: window.frame.midY) }

    init() {
        let size = NSSize(width: 74, height: 74)
        window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = LocalBallView(frame: NSRect(origin: .zero, size: size))
    }

    func show(centeredAt point: CGPoint) {
        window.alphaValue = 1
        window.setFrameOrigin(CGPoint(x: point.x - window.frame.width / 2, y: point.y - window.frame.height / 2))
        window.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }

    func kick(direction: ShootDirection, completion: @escaping () -> Void) {
        guard let screen = window.screen ?? NSScreen.main else { completion(); return }
        let destinationX = direction == .left ? screen.frame.minX - window.frame.width : screen.frame.maxX + window.frame.width
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.48
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrameOrigin(CGPoint(x: destinationX, y: window.frame.minY + 25))
        } completionHandler: {
            self.window.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: completion)
        }
    }

    func bump(along vector: CGPoint) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        let x = min(max(window.frame.minX + vector.x * 78, bounds.minX), bounds.maxX - window.frame.width)
        let y = min(max(window.frame.minY + vector.y * 42, bounds.minY), bounds.maxY - window.frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(CGPoint(x: x, y: y))
        }
    }
}

private final class LocalBallView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        NSString(string: "⚽️").draw(
            in: bounds,
            withAttributes: [.font: NSFont.systemFont(ofSize: 54), .paragraphStyle: paragraph]
        )
    }
}

@MainActor
private final class PlayerView: NSView {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onKickAttempt: (() -> Void)?
    var onTackleAttempt: (() -> Void)?
    private(set) var heading: PlayerHeading
    private(set) var aimVector: CGPoint
    private let moveFrames: [NSImage]
    private let runFrames: [NSImage]
    private let runFrontFrames: [NSImage]
    private let runBackFrames: [NSImage]
    private let kickFrames: [NSImage]
    private let kickFrontFrames: [NSImage]
    private let kickSideFrames: [NSImage]
    private let tackleFrames: [NSImage]
    private let tackleFrontFrames: [NSImage]
    private let tackleBackFrames: [NSImage]
    private var pressedKeys = Set<UInt16>()
    private var sprintHeld = false
    private var movementVelocity = CGPoint.zero
    private var timer: Timer?
    private var runPhase: CGFloat = 0
    private var kickStartedAt: TimeInterval = -.infinity
    private var tackleStartedAt: TimeInterval = -.infinity
    private var stunnedUntil: TimeInterval = 0
    private var feedbackFrames = 0

    init(frame frameRect: NSRect, facing: ShootDirection) {
        heading = facing == .left ? .left : .right
        aimVector = heading.vector
        func frames(_ name: String, count: Int) -> [NSImage] {
            (1...count).compactMap { index in
                guard let url = ResourceBundle.images.url(forResource: String(format: "%@-%02d", name, index), withExtension: "png") else { return nil }
                return NSImage(contentsOf: url)
            }
        }
        moveFrames = frames("move", count: 4)
        runFrames = frames("run", count: 4)
        runFrontFrames = frames("run-front", count: 4)
        runBackFrames = frames("run-back", count: 4)
        kickFrames = frames("kick", count: 8)
        kickFrontFrames = frames("kick-front", count: 4)
        kickSideFrames = frames("kick-side", count: 4)
        tackleFrames = frames("tackle", count: 4)
        tackleFrontFrames = frames("tackle-front", count: 4)
        tackleBackFrames = frames("tackle-back", count: 4)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    required init?(coder: NSCoder) { nil }
    deinit { timer?.invalidate() }
    override var acceptsFirstResponder: Bool { true }

    func setFacing(_ direction: ShootDirection) {
        heading = direction == .left ? .left : .right
        aimVector = heading.vector
        needsDisplay = true
    }

    func didKick() { kickStartedAt = ProcessInfo.processInfo.systemUptime }

    func didTackle() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - tackleStartedAt >= 1.1, now - kickStartedAt >= 0.65 else { return false }
        tackleStartedAt = now
        needsDisplay = true
        return true
    }

    var isStunned: Bool { ProcessInfo.processInfo.systemUptime < stunnedUntil }

    func stun() {
        stunnedUntil = ProcessInfo.processInfo.systemUptime + 0.6
        pressedKeys.removeAll()
        movementVelocity = .zero
        needsDisplay = true
    }

    func showTooFarFeedback() { feedbackFrames = 45 }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124, 125, 126:
            pressedKeys.insert(event.keyCode)
        case 49: if !event.isARepeat { onKickAttempt?() }
        case 0: if !event.isARepeat { onTackleAttempt?() } // A
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if pressedKeys.contains(event.keyCode) { pressedKeys.remove(event.keyCode) }
        else { super.keyUp(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        sprintHeld = event.modifierFlags.contains(.shift)
        super.flagsChanged(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let now = ProcessInfo.processInfo.systemUptime
        let isRunning = hypot(movementVelocity.x, movementVelocity.y) > 0.5
        let sinceKick = now - kickStartedAt
        let sinceTackle = now - tackleStartedAt
        let sprite: NSImage?
        let height: CGFloat
        if sinceKick < 0.72 {
            let frames: [NSImage]
            let frameDuration: Double
            switch heading {
            case .down: frames = kickFrontFrames; frameDuration = 0.18
            case .left, .right, .downLeft, .downRight: frames = kickSideFrames; frameDuration = 0.18
            case .up, .upLeft, .upRight: frames = kickFrames; frameDuration = 0.09
            }
            sprite = frames.isEmpty ? nil : frames[min(frames.count - 1, Int(sinceKick / frameDuration))]
            height = 300
        } else if sinceTackle < 0.55 {
            let frames: [NSImage]
            switch heading {
            case .down: frames = tackleFrontFrames
            case .up, .upLeft, .upRight: frames = tackleBackFrames
            case .left, .right, .downLeft, .downRight: frames = tackleFrames
            }
            sprite = frames.isEmpty ? nil : frames[min(frames.count - 1, Int(sinceTackle / 0.13))]
            height = sinceTackle < 0.26 ? 310 : 180
        } else if isRunning {
            let frames: [NSImage]
            switch heading {
            case .down, .downLeft, .downRight: frames = runFrontFrames
            case .up, .upLeft, .upRight: frames = runBackFrames
            case .left, .right: frames = runFrames
            }
            sprite = frames.isEmpty ? nil : frames[Int(runPhase / 4) % frames.count]
            height = 315
        } else if !moveFrames.isEmpty {
            switch heading {
            case .down: sprite = moveFrames[0]
            case .downLeft, .downRight: sprite = moveFrames[1]
            case .left, .right: sprite = moveFrames[2]
            case .up, .upLeft, .upRight: sprite = moveFrames[3]
            }
            height = 330
        } else { sprite = nil; height = 330 }

        if let sprite { drawSprite(sprite, height: height, bob: isRunning && sinceKick >= 0.72 && sinceTackle >= 0.55 ? abs(sin(runPhase * 0.8)) * 4 : 0) }
        else { NSString(string: "SIU").draw(at: CGPoint(x: 110, y: 180), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 30)]) }
        drawDirectionIndicator()
        drawHint()
    }

    private func drawDirectionIndicator() {
        let center = CGPoint(x: bounds.midX, y: 42)
        let radius: CGFloat = 25
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2))
        NSColor.black.withAlphaComponent(0.54).setFill()
        circle.fill()
        circle.lineWidth = 2
        NSColor.white.withAlphaComponent(0.9).setStroke()
        circle.stroke()

        let tip = CGPoint(x: center.x + aimVector.x * 19, y: center.y + aimVector.y * 19)
        let base = CGPoint(x: center.x - aimVector.x * 6, y: center.y - aimVector.y * 6)
        let wing = CGPoint(x: -aimVector.y * 6, y: aimVector.x * 6)
        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: base.x + wing.x, y: base.y + wing.y))
        arrow.line(to: tip)
        arrow.line(to: CGPoint(x: base.x - wing.x, y: base.y - wing.y))
        arrow.close()
        NSColor.systemYellow.setFill()
        arrow.fill()
    }

    private func drawSprite(_ image: NSImage, height: CGFloat, bob: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if heading.isMirrored {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        let ratio = min(height / image.size.height, 255 / image.size.width)
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: 8 + bob, width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
    }

    private func drawHint() {
        let text = isStunned ? "태클당함!" : (feedbackFrames > 0 ? "공에 더 가까이 가세요!" : "방향키 이동·방향 · Space 슛 · A 태클")
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        NSString(string: text).draw(
            in: NSRect(x: 10, y: 365, width: 250, height: 22),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: feedbackFrames > 0 ? NSColor.systemRed : NSColor.labelColor,
                             .paragraphStyle: paragraph]
        )
    }

    private func tick() {
        if window?.isKeyWindow != true { pressedKeys.removeAll(); sprintHeld = false; movementVelocity = .zero }
        let dx = CGFloat((pressedKeys.contains(124) ? 1 : 0) - (pressedKeys.contains(123) ? 1 : 0))
        let dy = CGFloat((pressedKeys.contains(126) ? 1 : 0) - (pressedKeys.contains(125) ? 1 : 0))
        let length = hypot(dx, dy)
        if !isStunned && length > 0 {
            let targetAngle = atan2(dy, dx)
            let currentAngle = atan2(aimVector.y, aimVector.x)
            let difference = atan2(sin(targetAngle - currentAngle), cos(targetAngle - currentAngle))
            let turn = min(max(difference, -0.18), 0.18)
            let angle = currentAngle + turn
            aimVector = CGPoint(x: cos(angle), y: sin(angle))
            heading = PlayerHeading(dx: aimVector.x, dy: aimVector.y)
        }
        let speed: CGFloat = sprintHeld ? 9 : 5
        let target = !isStunned && length > 0
            ? CGPoint(x: dx / length * speed, y: dy / length * speed) : .zero
        let smoothing: CGFloat = length > 0 ? 0.24 : 0.28
        movementVelocity.x += (target.x - movementVelocity.x) * smoothing
        movementVelocity.y += (target.y - movementVelocity.y) * smoothing
        let movementSpeed = hypot(movementVelocity.x, movementVelocity.y)
        if movementSpeed > 0.08 && !isStunned {
            onMove?(movementVelocity.x, movementVelocity.y)
            runPhase += movementSpeed / speed
        } else if length == 0 || isStunned {
            movementVelocity = .zero
        }
        feedbackFrames = max(0, feedbackFrames - 1)
        needsDisplay = true
    }
}
