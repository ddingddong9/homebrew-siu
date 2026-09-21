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

@MainActor
final class PlayerWindowController: NSWindowController {
    var onKick: ((ShootDirection, Double, Double) -> Void)?
    private let playerView: PlayerView
    private var dockSide: PlayerDockSide

    init() {
        let dockSide = PlayerDockSide.from(ScreenLayoutStore.load())
        self.dockSide = dockSide
        let size = NSSize(width: 320, height: 410)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        let player = PlayerView(frame: NSRect(origin: .zero, size: size), dockSide: dockSide)
        self.playerView = player
        panel.contentView = player
        super.init(window: panel)
        player.onKick = { [weak self] direction, y, power in
            self?.onKick?(direction, y, power)
        }
        positionAtConfiguredSide()
    }

    required init?(coder: NSCoder) { nil }

    func toggle() -> Bool {
        guard let window else { return false }
        if window.isVisible {
            window.orderOut(nil)
            return false
        }
        refreshLayout()
        window.orderFrontRegardless()
        return true
    }

    func show() {
        refreshLayout()
        window?.orderFrontRegardless()
    }

    func refreshLayout() {
        dockSide = PlayerDockSide.from(ScreenLayoutStore.load())
        playerView.setDockSide(dockSide)
        positionAtConfiguredSide()
    }

    private func positionAtConfiguredSide() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let window else { return }
        let frame = screen.visibleFrame
        let x = dockSide == .right ? frame.maxX - window.frame.width - 12 : frame.minX + 12
        window.setFrameOrigin(NSPoint(x: x, y: frame.minY + 8))
    }
}

@MainActor
private final class PlayerView: NSView {
    var onKick: ((ShootDirection, Double, Double) -> Void)?
    private var dockSide: PlayerDockSide
    private let character: NSImage?
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var dragStartX: CGFloat?
    private var charge: CGFloat = 0
    private var kickPulse: CGFloat = 0

    init(frame frameRect: NSRect, dockSide: PlayerDockSide) {
        self.dockSide = dockSide
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

    func setDockSide(_ side: PlayerDockSide) {
        dockSide = side
        dragStartX = nil
        charge = 0
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = convert(event.locationInWindow, from: nil).x
        charge = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let kickDirection: CGFloat = dockSide == .right ? -1 : 1
        let backwardDistance = -(x - dragStartX) * kickDirection
        charge = min(max(backwardDistance / 95, 0), 1)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartX = nil
            charge = 0
            needsDisplay = true
        }
        guard charge >= 0.16 else { return }
        let direction: ShootDirection = dockSide == .right ? .left : .right
        let power = Double(charge)
        kickPulse = 1
        onKick?(direction, 0.16, power)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let character else {
            NSString(string: "SIU").draw(at: CGPoint(x: 120, y: 180), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 30)])
            return
        }

        let imageSize = character.size
        let characterHeight: CGFloat = 360
        let scale = characterHeight / imageSize.height
        let characterWidth = imageSize.width * scale
        let origin = CGPoint(x: (bounds.width - characterWidth) / 2, y: 8)
        let fullRect = NSRect(origin: origin, size: NSSize(width: characterWidth, height: characterHeight))
        let cutY = imageSize.height * 0.285
        let cutDestY = origin.y + cutY * scale

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if dockSide == .right {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: origin.x, y: cutDestY, width: characterWidth, height: characterHeight - cutY * scale)).addClip()
        character.draw(in: fullRect, from: NSRect(origin: .zero, size: imageSize), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()

        let idle = sin(phase) * 0.055
        let chargedAngle = -charge * 0.48
        let kickAngle = kickPulse * 0.62
        drawLeg(character, fullRect: fullRect, imageSize: imageSize,
                crop: NSRect(x: imageSize.width * 0.20, y: 0, width: imageSize.width * 0.33, height: cutY * 1.12),
                pivot: CGPoint(x: origin.x + imageSize.width * 0.38 * scale, y: origin.y + cutY * scale),
                angle: idle * -1)
        drawLeg(character, fullRect: fullRect, imageSize: imageSize,
                crop: NSRect(x: imageSize.width * 0.48, y: 0, width: imageSize.width * 0.33, height: cutY * 1.12),
                pivot: CGPoint(x: origin.x + imageSize.width * 0.64 * scale, y: origin.y + cutY * scale),
                angle: chargedAngle + kickAngle + idle)
        context.restoreGState()

        drawHint()
        if charge > 0 { drawPowerBar() }
    }

    private func drawLeg(_ image: NSImage, fullRect: NSRect, imageSize: NSSize, crop: NSRect, pivot: CGPoint, angle: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: pivot.x, y: pivot.y)
        context.rotate(by: angle)
        context.translateBy(x: -pivot.x, y: -pivot.y)
        let scaleX = fullRect.width / imageSize.width
        let scaleY = fullRect.height / imageSize.height
        let clip = NSRect(
            x: fullRect.minX + crop.minX * scaleX,
            y: fullRect.minY + crop.minY * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        )
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        image.draw(in: fullRect, from: NSRect(origin: .zero, size: imageSize), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
        context.restoreGState()
    }

    private func drawHint() {
        let text = dragStartX == nil ? "누르고 반대쪽으로 당겨 슛" : "놓으면 SIU!"
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        NSString(string: text).draw(
            in: NSRect(x: 35, y: 382, width: 250, height: 22),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: NSColor.labelColor,
                             .paragraphStyle: paragraph]
        )
    }

    private func drawPowerBar() {
        let track = NSRect(x: 95, y: 3, width: 130, height: 8)
        NSColor.black.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * charge, height: track.height), xRadius: 4, yRadius: 4).fill()
    }

    private func tick() {
        phase += 0.09
        if kickPulse > 0 {
            kickPulse = max(0, kickPulse - 0.08)
        }
        needsDisplay = true
    }
}
