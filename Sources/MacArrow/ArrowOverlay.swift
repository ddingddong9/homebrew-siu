import AppKit

@MainActor
final class ArrowOverlayController {
    private var windows: [NSWindow] = []

    func clearAll() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func showArrow(normalizedY: Double, entryEdge: String = "right") {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = ArrowView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.normalizedY = normalizedY
        view.entersFromRight = entryEdge != "left"
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)
        view.animate()
    }
}

private final class ArrowView: NSView {
    var normalizedY = 0.5
    var entersFromRight = true
    private let arrowLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        arrowLayer.strokeColor = NSColor.systemRed.cgColor
        arrowLayer.fillColor = NSColor.systemRed.cgColor
        arrowLayer.lineWidth = 5
        arrowLayer.lineCap = .round
        layer?.addSublayer(arrowLayer)
    }

    required init?(coder: NSCoder) { nil }

    func animate() {
        layoutSubtreeIfNeeded()
        let y = bounds.height * CGFloat(normalizedY)
        let path = makeArrowPath(pointingLeft: entersFromRight)
        arrowLayer.path = path
        let startX = entersFromRight ? bounds.width + 140 : -140
        let endX = entersFromRight ? bounds.width * 0.70 : bounds.width * 0.30
        arrowLayer.position = CGPoint(x: startX, y: y)

        CATransaction.begin()
        let flight = CABasicAnimation(keyPath: "position.x")
        flight.fromValue = startX
        flight.toValue = endX
        flight.duration = 0.48
        flight.timingFunction = CAMediaTimingFunction(name: .easeOut)
        arrowLayer.position.x = endX
        arrowLayer.add(flight, forKey: "flight")
        CATransaction.commit()
    }

    private func makeArrowPath(pointingLeft: Bool) -> CGPath {
        let tipX: CGFloat = pointingLeft ? 0 : 120
        let tailX: CGFloat = pointingLeft ? 120 : 0
        let innerX: CGFloat = pointingLeft ? 22 : 98
        let featherX: CGFloat = pointingLeft ? 102 : 18
        let path = CGMutablePath()
        path.move(to: CGPoint(x: tipX, y: 0)); path.addLine(to: CGPoint(x: tailX, y: 0))
        path.move(to: CGPoint(x: tipX, y: 0)); path.addLine(to: CGPoint(x: innerX, y: 15))
        path.move(to: CGPoint(x: tipX, y: 0)); path.addLine(to: CGPoint(x: innerX, y: -15))
        path.move(to: CGPoint(x: tailX, y: 0)); path.addLine(to: CGPoint(x: featherX, y: 10))
        path.move(to: CGPoint(x: tailX, y: 0)); path.addLine(to: CGPoint(x: featherX, y: -10))
        return path
    }
}
