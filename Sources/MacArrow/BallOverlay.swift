import AppKit

@MainActor
final class BallOverlayController {
    private var windows: [NSWindow] = []

    func clearAll() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func showBall(normalizedY: Double, entryEdge: String = "right") {
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

        let view = BallFlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.normalizedY = normalizedY
        view.entersFromRight = entryEdge != "left"
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)
        view.animate()
    }
}

private final class BallFlightView: NSView {
    var normalizedY = 0.5
    var entersFromRight = true
    private let ballLayer = CATextLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        ballLayer.string = "⚽️"
        ballLayer.fontSize = 62
        ballLayer.alignmentMode = .center
        ballLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        ballLayer.bounds = CGRect(x: 0, y: 0, width: 82, height: 82)
        layer?.addSublayer(ballLayer)
    }

    required init?(coder: NSCoder) { nil }

    func animate() {
        layoutSubtreeIfNeeded()
        let y = bounds.height * CGFloat(normalizedY)
        let startX = entersFromRight ? bounds.width + 90 : -90
        let endX = entersFromRight ? bounds.width * 0.70 : bounds.width * 0.30
        ballLayer.position = CGPoint(x: startX, y: y)

        let flight = CABasicAnimation(keyPath: "position.x")
        flight.fromValue = startX
        flight.toValue = endX
        flight.duration = 0.62
        flight.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = entersFromRight ? -Double.pi * 5 : Double.pi * 5
        spin.duration = flight.duration

        ballLayer.position.x = endX
        ballLayer.add(flight, forKey: "flight")
        ballLayer.add(spin, forKey: "spin")
    }
}
