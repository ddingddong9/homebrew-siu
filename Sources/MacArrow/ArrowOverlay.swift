import AppKit

@MainActor
final class ArrowOverlayController {
    private var windows: [NSWindow] = []

    func showArrow(normalizedY: Double) {
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
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)
        view.animate()
    }
}

private final class ArrowView: NSView {
    var normalizedY = 0.5
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
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 120, y: 0))
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 22, y: 15))
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 22, y: -15))
        path.move(to: CGPoint(x: 120, y: 0))
        path.addLine(to: CGPoint(x: 102, y: 10))
        path.move(to: CGPoint(x: 120, y: 0))
        path.addLine(to: CGPoint(x: 102, y: -10))
        arrowLayer.path = path
        arrowLayer.position = CGPoint(x: bounds.width + 140, y: y)

        CATransaction.begin()
        let flight = CABasicAnimation(keyPath: "position.x")
        flight.fromValue = bounds.width + 140
        flight.toValue = bounds.width * 0.70
        flight.duration = 0.48
        flight.timingFunction = CAMediaTimingFunction(name: .easeOut)
        arrowLayer.position.x = bounds.width * 0.70
        arrowLayer.add(flight, forKey: "flight")
        CATransaction.commit()
    }
}
