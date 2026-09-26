import AppKit

@MainActor
final class MatchHUDController {
    private var window: NSWindow?
    private var view: MatchHUDView?

    func show(ownGoal: FieldEdge) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        hide()
        let panel = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered,
                             defer: false, screen: screen)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let content = MatchHUDView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.ownGoal = ownGoal
        panel.contentView = content
        panel.orderFrontRegardless()
        window = panel
        view = content
    }

    func update(ball: MatchBall?, myScore: Int, theirScore: Int, remaining: TimeInterval,
                status: String, remotePlayers: [CGPoint] = []) {
        view?.ball = ball
        view?.myScore = myScore
        view?.theirScore = theirScore
        view?.remaining = remaining
        view?.status = status
        view?.remotePlayers = remotePlayers
        view?.needsDisplay = true
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}

private final class MatchHUDView: NSView {
    var ownGoal: FieldEdge = .right
    var ball: MatchBall?
    var myScore = 0
    var theirScore = 0
    var remaining: TimeInterval = 0
    var status = ""
    var remotePlayers: [CGPoint] = []
    private let character: NSImage? = {
        guard let url = Bundle.module.url(forResource: "move-04", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawGoal()
        drawScoreboard()
        drawRemotePlayers()
        if let ball { drawBall(ball) }
    }

    private func drawGoal() {
        let x: CGFloat = ownGoal == .right ? bounds.maxX - 28 : bounds.minX + 28
        let minY = bounds.height * 0.10
        let maxY = bounds.height * 0.42
        let path = NSBezierPath()
        path.lineWidth = 6
        path.move(to: CGPoint(x: x, y: minY))
        path.line(to: CGPoint(x: x, y: maxY))
        let inset: CGFloat = ownGoal == .right ? -38 : 38
        path.move(to: CGPoint(x: x, y: minY))
        path.line(to: CGPoint(x: x + inset, y: minY + 15))
        path.line(to: CGPoint(x: x + inset, y: maxY - 15))
        path.line(to: CGPoint(x: x, y: maxY))
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
        let net = NSBezierPath()
        net.lineWidth = 1
        for step in 1...5 {
            let y = minY + (maxY - minY) * CGFloat(step) / 6
            net.move(to: CGPoint(x: x, y: y))
            net.line(to: CGPoint(x: x + inset, y: y))
        }
        NSColor.white.withAlphaComponent(0.4).setStroke()
        net.stroke()
    }

    private func drawScoreboard() {
        let minutes = Int(max(0, remaining)) / 60
        let seconds = Int(max(0, remaining)) % 60
        let text = "나 \(myScore)  :  \(theirScore) 상대     \(String(format: "%02d:%02d", minutes, seconds))"
        let board = NSRect(x: (bounds.width - 370) / 2, y: bounds.height - 82, width: 370, height: 52)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: board, xRadius: 14, yRadius: 14).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSString(string: text).draw(in: board.insetBy(dx: 8, dy: 11), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
        if !status.isEmpty {
            NSString(string: status).draw(in: NSRect(x: board.minX, y: board.minY - 28, width: board.width, height: 22), withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ])
        }
    }

    private func drawBall(_ ball: MatchBall) {
        let size: CGFloat = 46
        NSString(string: "⚽️").draw(in: NSRect(x: bounds.width * ball.x - size / 2,
                                                y: bounds.height * ball.y - size / 2,
                                                width: size, height: size),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 38)])
    }

    private func drawRemotePlayers() {
        guard let character else { return }
        for point in remotePlayers {
            let height: CGFloat = 135
            let width = height * character.size.width / character.size.height
            let rect = NSRect(x: bounds.width * point.x - width / 2,
                              y: bounds.height * point.y - 25,
                              width: width, height: height)
            character.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.65)
        }
    }
}
