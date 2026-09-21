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

private final class GamePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PlayerWindowController: NSWindowController {
    var onKick: ((ShootDirection, Double, Double) -> Bool)?
    private let playerView: PlayerView
    private let ball = LocalBallWindowController()
    private var dockSide: PlayerDockSide
    private var facing: ShootDirection
    private var ballIsFlying = false

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
        resetBall()
    }

    func refreshLayout() {
        dockSide = PlayerDockSide.from(ScreenLayoutStore.load())
        facing = dockSide == .right ? .left : .right
        playerView.setFacing(facing)
        positionAtConfiguredSide()
        if window?.isVisible == true { resetBall() }
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
        playerView.setFacing(facing)
        playerView.didWalk()
    }

    private func tryKick() {
        guard !ballIsFlying, let window else { return }
        let playerFoot = CGPoint(x: window.frame.midX, y: window.frame.minY + 42)
        let ballCenter = ball.center
        let distance = hypot(playerFoot.x - ballCenter.x, playerFoot.y - ballCenter.y)
        guard distance <= 125 else {
            playerView.showTooFarFeedback()
            return
        }
        guard onKick?(facing, 0.16, 1) == true else { return }
        ballIsFlying = true
        playerView.didKick()
        ball.kick(direction: facing) { [weak self] in
            guard let self else { return }
            self.ballIsFlying = false
            self.resetBall()
        }
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
    private var facing: ShootDirection
    private let character: NSImage?
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var walkPulse: CGFloat = 0
    private var kickPulse: CGFloat = 0
    private var feedbackFrames = 0

    init(frame frameRect: NSRect, facing: ShootDirection) {
        self.facing = facing
        if let url = Bundle.module.url(forResource: "siu-character", withExtension: "png") {
            self.character = NSImage(contentsOf: url)
        } else {
            self.character = nil
        }
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
        facing = direction
        needsDisplay = true
    }

    func didWalk() { walkPulse = 1 }
    func didKick() { kickPulse = 1 }
    func showTooFarFeedback() { feedbackFrames = 45 }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 34 : 18
        switch event.keyCode {
        case 123: onMove?(-step, 0)
        case 124: onMove?(step, 0)
        case 125: onMove?(0, -step)
        case 126: onMove?(0, step)
        case 49: onKickAttempt?()
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let character else {
            NSString(string: "SIU").draw(at: CGPoint(x: 110, y: 180), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 30)])
            return
        }

        let imageSize = character.size
        let characterHeight: CGFloat = 350
        let scale = characterHeight / imageSize.height
        let characterWidth = imageSize.width * scale
        let origin = CGPoint(x: (bounds.width - characterWidth) / 2, y: 5)
        let fullRect = NSRect(origin: origin, size: NSSize(width: characterWidth, height: characterHeight))
        let cutY = imageSize.height * 0.285
        let cutDestY = origin.y + cutY * scale

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if facing == .left {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: origin.x, y: cutDestY, width: characterWidth, height: characterHeight - cutY * scale)).addClip()
        character.draw(in: fullRect, from: NSRect(origin: .zero, size: imageSize), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()

        let stride = sin(phase) * 0.20 * walkPulse
        let kick = kickPulse * 0.68
        drawLeg(character, fullRect: fullRect, imageSize: imageSize,
                crop: NSRect(x: imageSize.width * 0.20, y: 0, width: imageSize.width * 0.33, height: cutY * 1.12),
                pivot: CGPoint(x: origin.x + imageSize.width * 0.38 * scale, y: origin.y + cutY * scale),
                angle: -stride)
        drawLeg(character, fullRect: fullRect, imageSize: imageSize,
                crop: NSRect(x: imageSize.width * 0.48, y: 0, width: imageSize.width * 0.33, height: cutY * 1.12),
                pivot: CGPoint(x: origin.x + imageSize.width * 0.64 * scale, y: origin.y + cutY * scale),
                angle: stride + kick)
        context.restoreGState()
        drawHint()
    }

    private func drawLeg(_ image: NSImage, fullRect: NSRect, imageSize: NSSize, crop: NSRect, pivot: CGPoint, angle: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: pivot.x, y: pivot.y)
        context.rotate(by: angle)
        context.translateBy(x: -pivot.x, y: -pivot.y)
        let scaleX = fullRect.width / imageSize.width
        let scaleY = fullRect.height / imageSize.height
        let clip = NSRect(x: fullRect.minX + crop.minX * scaleX,
                          y: fullRect.minY + crop.minY * scaleY,
                          width: crop.width * scaleX,
                          height: crop.height * scaleY)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        image.draw(in: fullRect, from: NSRect(origin: .zero, size: imageSize), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
        context.restoreGState()
    }

    private func drawHint() {
        let text = feedbackFrames > 0 ? "공에 더 가까이 가세요!" : "← ↑ ↓ → 이동   SPACE 슛"
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        NSString(string: text).draw(
            in: NSRect(x: 10, y: 365, width: 250, height: 22),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: feedbackFrames > 0 ? NSColor.systemRed : NSColor.labelColor,
                             .paragraphStyle: paragraph]
        )
    }

    private func tick() {
        phase += 0.22
        walkPulse = max(0, walkPulse - 0.035)
        kickPulse = max(0, kickPulse - 0.075)
        feedbackFrames = max(0, feedbackFrames - 1)
        needsDisplay = true
    }
}
