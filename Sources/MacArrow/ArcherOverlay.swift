import AppKit

private enum ArcherDockSide {
    case left
    case right

    static func from(_ layout: ScreenLayout) -> ArcherDockSide {
        guard let local = layout.screens.first(where: \.isLocal) else { return .right }
        let peers = layout.screens.filter { !$0.isLocal }
        guard !peers.isEmpty else { return .right }
        let averagePeerX = peers.map(\.x).reduce(0, +) / Double(peers.count)
        return local.x >= averagePeerX ? .right : .left
    }
}

@MainActor
final class ArcherWindowController: NSWindowController {
    var onFire: ((ShootDirection, Double, Double) -> Void)?
    private let archerView: ArcherView
    private var dockSide: ArcherDockSide

    init() {
        let dockSide = ArcherDockSide.from(ScreenLayoutStore.load())
        self.dockSide = dockSide
        let size = NSSize(width: 330, height: 270)
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
        let archer = ArcherView(frame: NSRect(origin: .zero, size: size), dockSide: dockSide)
        self.archerView = archer
        panel.contentView = archer
        super.init(window: panel)
        archer.onFire = { [weak self] direction, y, power in
            self?.onFire?(direction, y, power)
        }
        positionAtBottomRight()
    }

    required init?(coder: NSCoder) { nil }

    func toggle() -> Bool {
        guard let window else { return false }
        if window.isVisible {
            window.orderOut(nil)
            return false
        }
        positionAtBottomRight()
        window.orderFrontRegardless()
        return true
    }

    func show() {
        refreshLayout()
        positionAtBottomRight()
        window?.orderFrontRegardless()
    }

    func refreshLayout() {
        dockSide = ArcherDockSide.from(ScreenLayoutStore.load())
        archerView.setDockSide(dockSide)
        positionAtConfiguredSide()
    }

    private func positionAtBottomRight() {
        positionAtConfiguredSide()
    }

    private func positionAtConfiguredSide() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let window else { return }
        let frame = screen.visibleFrame
        let x = dockSide == .right ? frame.maxX - window.frame.width - 18 : frame.minX + 18
        window.setFrameOrigin(NSPoint(x: x, y: frame.minY + 18))
    }
}

@MainActor
private final class ArcherView: NSView {
    var onFire: ((ShootDirection, Double, Double) -> Void)?
    private var dockSide: ArcherDockSide
    private var bowCenter: CGPoint { CGPoint(x: dockSide == .right ? 138 : 192, y: 112) }
    private var bodyX: CGFloat { dockSide == .right ? 205 : 125 }
    private var aim: CGVector
    private var frozenAim: CGVector?
    private var pull: CGFloat = 0
    private var timer: Timer?

    init(frame frameRect: NSRect, dockSide: ArcherDockSide) {
        self.dockSide = dockSide
        self.aim = dockSide == .right ? CGVector(dx: -1, dy: 0) : CGVector(dx: 1, dy: 0)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followMouse() }
        }
    }

    required init?(coder: NSCoder) { nil }
    deinit { timer?.invalidate() }

    override var acceptsFirstResponder: Bool { true }

    func setDockSide(_ side: ArcherDockSide) {
        dockSide = side
        aim = side == .right ? CGVector(dx: -1, dy: 0) : CGVector(dx: 1, dy: 0)
        frozenAim = nil
        pull = 0
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        frozenAim = aim
        pull = 0
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let frozenAim else { return }
        let point = convert(event.locationInWindow, from: nil)
        let vectorFromBow = CGVector(dx: point.x - bowCenter.x, dy: point.y - bowCenter.y)
        let backward = -(vectorFromBow.dx * frozenAim.dx + vectorFromBow.dy * frozenAim.dy)
        pull = min(max(backward, 0), 86)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let firedAim = frozenAim else { return }
        let firedPower = pull
        frozenAim = nil
        pull = 0
        needsDisplay = true
        guard firedPower >= 18 else { return }
        let direction: ShootDirection = firedAim.dx < 0 ? .left : .right
        let globalPoint = window?.convertPoint(toScreen: bowCenter) ?? NSEvent.mouseLocation
        let screen = window?.screen ?? NSScreen.main
        let normalizedY = screen.map { (globalPoint.y - $0.frame.minY) / $0.frame.height } ?? 0.5
        onFire?(direction, Double(normalizedY), Double(firedPower / 86))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let activeAim = frozenAim ?? aim
        drawHint()
        drawArcher(aim: activeAim)
        drawBowAndArrow(aim: activeAim)
    }

    private func followMouse() {
        guard frozenAim == nil, let window else { return }
        let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let dx = local.x - bowCenter.x
        let dy = local.y - bowCenter.y
        let length = max(hypot(dx, dy), 1)
        aim = CGVector(dx: dx / length, dy: dy / length)
        needsDisplay = true
    }

    private func drawArcher(aim: CGVector) {
        let ink = NSColor.labelColor.withAlphaComponent(0.92)
        ink.setStroke()
        let body = NSBezierPath()
        body.lineWidth = 5
        body.lineCapStyle = .round
        body.appendOval(in: NSRect(x: bodyX - 21, y: 154, width: 42, height: 42))
        body.move(to: CGPoint(x: bodyX, y: 154)); body.line(to: CGPoint(x: bodyX, y: 82))
        body.move(to: CGPoint(x: bodyX, y: 84)); body.line(to: CGPoint(x: bodyX - 32, y: 36))
        body.move(to: CGPoint(x: bodyX, y: 84)); body.line(to: CGPoint(x: bodyX + 31, y: 36))
        body.move(to: CGPoint(x: bodyX, y: 138)); body.line(to: bowCenter)
        let nock = CGPoint(x: bowCenter.x - aim.dx * pull, y: bowCenter.y - aim.dy * pull)
        body.move(to: CGPoint(x: bodyX, y: 138)); body.line(to: nock)
        body.stroke()
    }

    private func drawBowAndArrow(aim: CGVector) {
        let perpendicular = CGVector(dx: -aim.dy, dy: aim.dx)
        let top = point(bowCenter, plus: perpendicular, times: 58)
        let bottom = point(bowCenter, plus: perpendicular, times: -58)
        let belly = point(bowCenter, plus: aim, times: -22)
        let nock = point(bowCenter, plus: aim, times: -pull)

        NSColor.systemBrown.setStroke()
        let bow = NSBezierPath()
        bow.lineWidth = 6
        bow.lineCapStyle = .round
        bow.move(to: top)
        bow.curve(to: bottom,
                  controlPoint1: point(top, plus: aim, times: -28),
                  controlPoint2: point(bottom, plus: aim, times: -28))
        bow.stroke()

        NSColor.secondaryLabelColor.setStroke()
        let string = NSBezierPath()
        string.lineWidth = 2
        string.move(to: top); string.line(to: nock); string.line(to: bottom)
        string.stroke()

        NSColor.systemRed.setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 4
        arrow.lineCapStyle = .round
        arrow.move(to: point(nock, plus: aim, times: -10))
        let tip = point(nock, plus: aim, times: 112)
        arrow.line(to: tip)
        arrow.move(to: tip)
        arrow.line(to: point(point(tip, plus: aim, times: -18), plus: perpendicular, times: 9))
        arrow.move(to: tip)
        arrow.line(to: point(point(tip, plus: aim, times: -18), plus: perpendicular, times: -9))
        arrow.stroke()

        if pull > 0 {
            let powerRect = NSRect(x: 92, y: 12, width: 100, height: 8)
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: powerRect, xRadius: 4, yRadius: 4).fill()
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: NSRect(x: powerRect.minX, y: powerRect.minY, width: powerRect.width * pull / 86, height: 8), xRadius: 4, yRadius: 4).fill()
        }
        _ = belly
    }

    private func drawHint() {
        let text = frozenAim == nil ? "누르고 뒤로 당겨 발사" : "당겼다가 놓으세요"
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        NSString(string: text).draw(
            in: NSRect(x: 55, y: 230, width: 230, height: 24),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                             .foregroundColor: NSColor.secondaryLabelColor,
                             .paragraphStyle: paragraph]
        )
    }

    private func point(_ origin: CGPoint, plus vector: CGVector, times scale: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + vector.dx * scale, y: origin.y + vector.dy * scale)
    }
}
