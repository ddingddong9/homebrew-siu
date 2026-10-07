import AppKit

@MainActor
final class ArenaWindowController: NSWindowController, NSWindowDelegate {
    var onKick: ((CGPoint, CGPoint) -> Void)?
    var onTackle: ((CGPoint, CGPoint) -> Void)?
    var onPowerShot: ((CGPoint) -> Void)?
    var onMarseille: (() -> Void)?
    var onRainbow: (() -> Void)?
    var onPhantom: ((Double) -> Void)?
    var onCurveShot: ((CGPoint, CGPoint) -> Void)?
    var onStepover: (() -> Void)?
    var onBackheel: (() -> Void)?
    var onPauseToggle: (() -> Void)?
    var onResume: (() -> Void)?
    var onEnd: (() -> Void)?
    var onClose: (() -> Void)?
    private let arenaView: ArenaView
    private var pausePanel: NSPanel?

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
        view.onPowerShot = { [weak self] position in self?.onPowerShot?(position) }
        view.onMarseille = { [weak self] in self?.onMarseille?() }
        view.onRainbow = { [weak self] in self?.onRainbow?() }
        view.onPhantom = { [weak self] vertical in self?.onPhantom?(vertical) }
        view.onCurveShot = { [weak self] position, direction in self?.onCurveShot?(position, direction) }
        view.onStepover = { [weak self] in self?.onStepover?() }
        view.onBackheel = { [weak self] in self?.onBackheel?() }
        view.onPauseToggle = { [weak self] in self?.onPauseToggle?() }
    }

    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === pausePanel { onResume?(); return false }
        onClose?()
        return false
    }

    func show(homeSide: FieldEdge) {
        arenaView.effectsEnabled = UserDefaults.standard.object(forKey: "SIUEffectsEnabled") as? Bool ?? true
        arenaView.reset(homeSide: homeSide)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(arenaView)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func hide() {
        setPaused(false)
        window?.orderOut(nil)
    }
    func advance(dt: TimeInterval) { arenaView.advance(dt: dt) }
    var localPosition: CGPoint { arenaView.localPosition }
    var localDirection: CGPoint { arenaView.localDirection }
    var stamina: Double { arenaView.motion.stamina }
    var isSliding: Bool { arenaView.motion.isSliding }
    @discardableResult func startSlide() -> Bool { arenaView.startSlide() }
    func setRemoteStamina(_ value: Double) { arenaView.remoteStamina = value }
    var remotePosition: CGPoint { arenaView.remotePosition }
    var isLocalFallen: Bool { arenaView.isLocalFallen }
    func stun() { arenaView.stun() }
    func stunRemote() { arenaView.stunRemote() }
    func resetForKickoff(conceding side: FieldEdge) { arenaView.resetForKickoff(conceding: side) }
    func startPowerCinematic(local: Bool) { arenaView.startPowerCinematic(local: local) }
    func startMarseille(local: Bool) { arenaView.startMarseille(local: local) }
    func marseilleProgress(side: FieldEdge) -> Double? { arenaView.marseilleProgress(side: side) }
    func startPhantom(local: Bool, vertical: Double) { arenaView.startPhantom(local: local, vertical: vertical) }
    func phantomProgress(side: FieldEdge) -> Double? { arenaView.phantomProgress(side: side) }
    func animateRainbow(local: Bool) { arenaView.animateRainbow(local: local) }
    func animateSpecial(_ move: SpecialMove, local: Bool, elapsed: TimeInterval = 0) { arenaView.animateSpecial(move, local: local, elapsed: elapsed) }
    func specialProgress(side: FieldEdge, move: SpecialMove? = nil) -> Double? { arenaView.specialProgress(side: side, move: move) }
    func setFireBall(_ active: Bool) { arenaView.fireBall = active; arenaView.needsDisplay = true }
    func animateRemoteKick() { arenaView.remoteKickAt = ProcessInfo.processInfo.systemUptime }
    func animateRemoteTackle() { arenaView.remoteTackleAt = ProcessInfo.processInfo.systemUptime }
    func showFeedback(_ message: String) { arenaView.showFeedback(message) }
    func setRemote(position: CGPoint, direction: CGPoint) {
        arenaView.remoteTarget = position
        arenaView.remoteDirection = direction
        arenaView.needsDisplay = true
    }

    func setPaused(_ paused: Bool, elapsed: TimeInterval = 0) {
        arenaView.setPaused(paused, elapsed: elapsed)
        if paused { showPausePanel() }
        else if let panel = pausePanel {
            window?.removeChildWindow(panel)
            panel.orderOut(nil)
            pausePanel = nil
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(arenaView)
        }
    }

    private func showPausePanel() {
        guard pausePanel == nil, let window else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "경기 설정 · 일시정지"
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 240))
        let title = NSTextField(labelWithString: "경기가 일시정지됐습니다")
        title.font = .boldSystemFont(ofSize: 19)
        title.alignment = .center
        title.frame = NSRect(x: 20, y: 184, width: 300, height: 30)
        content.addSubview(title)
        let instructions = NSTextField(labelWithString: "방향키 이동 · D 슛 · A 태클 · S 사포 · X 팬텀 · Z 턴")
        instructions.alignment = .center
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 20, y: 152, width: 300, height: 22)
        content.addSubview(instructions)
        let effects = NSButton(checkboxWithTitle: "화면 효과 표시", target: self,
                               action: #selector(toggleEffects(_:)))
        effects.state = arenaView.effectsEnabled ? .on : .off
        effects.frame = NSRect(x: 86, y: 112, width: 190, height: 26)
        content.addSubview(effects)
        let resume = NSButton(title: "계속하기 (Esc)", target: self, action: #selector(resumePressed))
        resume.frame = NSRect(x: 28, y: 42, width: 137, height: 38)
        resume.keyEquivalent = "\u{1b}"
        content.addSubview(resume)
        let end = NSButton(title: "경기 종료", target: self, action: #selector(endPressed))
        end.frame = NSRect(x: 175, y: 42, width: 137, height: 38)
        content.addSubview(end)
        panel.contentView = content
        let frame = window.frame
        panel.setFrameOrigin(CGPoint(x: frame.midX - 170, y: frame.midY - 120))
        window.addChildWindow(panel, ordered: .above)
        pausePanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleEffects(_ sender: NSButton) {
        arenaView.effectsEnabled = sender.state == .on
        UserDefaults.standard.set(sender.state == .on, forKey: "SIUEffectsEnabled")
    }
    @objc private func resumePressed() { onResume?() }
    @objc private func endPressed() { onEnd?() }
    func render(ball: ArenaBall, myScore: Int, theirScore: Int,
                remaining: TimeInterval, status: String) {
        arenaView.updateBall(ball)
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
    var onPowerShot: ((CGPoint) -> Void)?
    var onMarseille: (() -> Void)?
    var onRainbow: (() -> Void)?
    var onPhantom: ((Double) -> Void)?
    var onCurveShot: ((CGPoint, CGPoint) -> Void)?
    var onStepover: (() -> Void)?
    var onBackheel: (() -> Void)?
    var onPauseToggle: (() -> Void)?
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
    var effectsEnabled = true
    var fireBall = false
    private(set) var localDirection = CGPoint(x: 1, y: 0)
    private var velocity = CGPoint.zero
    var motion = AthleteMotion()
    var remoteStamina = 100.0
    @discardableResult func startSlide() -> Bool {
        guard !paused, !isLocalFallen, motion.startSlide(direction:localDirection) else { return false }
        tackleAt = visualNow; velocity = .zero; return true
    }
    private var stunnedUntil: TimeInterval = 0
    private var remoteStunnedUntil: TimeInterval = 0
    private var fallStartedAt: TimeInterval = -.infinity
    private var remoteFallStartedAt: TimeInterval = -.infinity
    private let fallDuration: TimeInterval = 1.55
    private var paused = false
    private var pauseStartedAt: TimeInterval = 0
    private var powerStartedAt: TimeInterval = -.infinity
    private var powerFocusLocal = true
    private var localTurnAt: TimeInterval = -.infinity
    private var remoteTurnAt: TimeInterval = -.infinity
    private let turnDuration: TimeInterval = 0.72
    private var localPhantomAt: TimeInterval = -.infinity
    private var remotePhantomAt: TimeInterval = -.infinity
    private var phantomVertical: CGFloat = 1
    private let phantomDuration: TimeInterval = 0.20
    private var zHeld = false
    private var zConsumed = false
    private var homeSide: FieldEdge = .left
    private var keys = Set<UInt16>()
    private var sprint = false
    private var animationPhase = 0.0
    private var kickAt: TimeInterval = -.infinity
    private var tackleAt: TimeInterval = -.infinity
    private var feedback = ""
    private var feedbackUntil: TimeInterval = 0
    private struct PlayingMove { var move: SpecialMove; var startedAt: TimeInterval }
    private var specialMoves: [Bool: PlayingMove] = [:]
    private let specialAnimations = Dictionary(uniqueKeysWithValues: SpecialMove.allCases.map { ($0, SpecialMoveAnimation($0)) })
    private var ballRotation: CGFloat = 0
    private var ballTrail: [(CGPoint, CGFloat)] = []
    private var bounceAt: TimeInterval = -.infinity
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
    var isLocalFallen: Bool { ProcessInfo.processInfo.systemUptime < stunnedUntil }

    func reset(homeSide: FieldEdge) {
        motion = AthleteMotion(); remoteStamina = 100
        self.homeSide = homeSide
        resetForKickoff(conceding: .left)
        paused = false
        fireBall = false
        powerStartedAt = -.infinity
        needsDisplay = true
    }

    func resetForKickoff(conceding side: FieldEdge) {
        motion.cancelSlide()
        specialMoves.removeAll()
        ballTrail.removeAll()
        ballRotation = 0
        bounceAt = -.infinity
        let positions = ArenaPhysics.startingX(conceding: side)
        localPosition = CGPoint(x: homeSide == .left ? positions.left : positions.right, y: 0.5)
        remotePosition = CGPoint(x: homeSide == .left ? positions.right : positions.left, y: 0.5)
        remoteTarget = remotePosition
        localDirection = CGPoint(x: homeSide == .left ? 1 : -1, y: 0)
        remoteDirection = CGPoint(x: -localDirection.x, y: 0)
        velocity = .zero
        stunnedUntil = 0
        remoteStunnedUntil = 0
        fallStartedAt = -.infinity
        remoteFallStartedAt = -.infinity
        kickAt = -.infinity
        tackleAt = -.infinity
        remoteKickAt = -.infinity
        remoteTackleAt = -.infinity
        powerStartedAt = -.infinity
        localTurnAt = -.infinity
        remoteTurnAt = -.infinity
        localPhantomAt = -.infinity
        remotePhantomAt = -.infinity
        zHeld = false
        zConsumed = false
        keys.removeAll()
        needsDisplay = true
    }

    func startPowerCinematic(local: Bool) {
        powerStartedAt = ProcessInfo.processInfo.systemUptime
        powerFocusLocal = local
        keys.removeAll()
        velocity = .zero
        needsDisplay = true
    }

    func startMarseille(local: Bool) {
        if local { localTurnAt = ProcessInfo.processInfo.systemUptime; velocity = .zero }
        else { remoteTurnAt = ProcessInfo.processInfo.systemUptime }
        needsDisplay = true
    }

    func marseilleProgress(side: FieldEdge) -> Double? {
        let started = side == homeSide ? localTurnAt : remoteTurnAt
        let elapsed = visualNow - started
        return (0..<turnDuration).contains(elapsed) ? elapsed / turnDuration : nil
    }

    func startPhantom(local: Bool, vertical: Double) {
        if local {
            localPhantomAt = ProcessInfo.processInfo.systemUptime
            phantomVertical = vertical >= 0 ? 1 : -1
            velocity = .zero
        } else { remotePhantomAt = ProcessInfo.processInfo.systemUptime }
        needsDisplay = true
    }

    func phantomProgress(side: FieldEdge) -> Double? {
        let started = side == homeSide ? localPhantomAt : remotePhantomAt
        let elapsed = visualNow - started
        return (0..<phantomDuration).contains(elapsed) ? elapsed / phantomDuration : nil
    }

    func animateRainbow(local: Bool) {
        if local { kickAt = ProcessInfo.processInfo.systemUptime }
        else { remoteKickAt = ProcessInfo.processInfo.systemUptime }
        needsDisplay = true
    }

    func animateSpecial(_ move: SpecialMove, local: Bool, elapsed: TimeInterval = 0) {
        if move == .backheel {
            if local { localDirection = CGPoint(x: -localDirection.x, y: -localDirection.y) }
            else { remoteDirection = CGPoint(x: -remoteDirection.x, y: -remoteDirection.y) }
        }
        specialMoves[local] = PlayingMove(move: move, startedAt: ProcessInfo.processInfo.systemUptime - max(0, elapsed))
        if local { velocity = .zero; keys.removeAll() }
        needsDisplay = true
    }

    func specialProgress(side: FieldEdge, move: SpecialMove? = nil) -> Double? {
        guard let state = specialMoves[side == homeSide], move == nil || state.move == move else { return nil }
        let elapsed = visualNow - state.startedAt
        return (0..<state.move.duration).contains(elapsed) ? elapsed / state.move.duration : nil
    }

    func updateBall(_ newBall: ArenaBall) {
        let distance = hypot(newBall.x - ball.x, newBall.y - ball.y)
        if !paused, distance > 0.0001 {
            if distance < 0.15 {
                ballRotation += CGFloat(distance) * bounds.width / 12
                ballTrail.append((point(newBall.x, newBall.y), CGFloat(newBall.z)))
                if ballTrail.count > 8 { ballTrail.removeFirst() }
            } else { ballTrail.removeAll() }
        }
        if !paused, ball.z > 0, newBall.z == 0, ball.vz < 0 { bounceAt = visualNow }
        ball = newBall
    }

    func setPaused(_ value: Bool, elapsed: TimeInterval) {
        if paused && !value && elapsed > 0 {
            for key in Array(specialMoves.keys) { specialMoves[key]?.startedAt += elapsed }
            if bounceAt.isFinite { bounceAt += elapsed }
            if stunnedUntil > 0 { stunnedUntil += elapsed }
            if remoteStunnedUntil > 0 { remoteStunnedUntil += elapsed }
            if fallStartedAt.isFinite { fallStartedAt += elapsed }
            if remoteFallStartedAt.isFinite { remoteFallStartedAt += elapsed }
            if powerStartedAt.isFinite { powerStartedAt += elapsed }
            if localTurnAt.isFinite { localTurnAt += elapsed }
            if remoteTurnAt.isFinite { remoteTurnAt += elapsed }
            if localPhantomAt.isFinite { localPhantomAt += elapsed }
            if remotePhantomAt.isFinite { remotePhantomAt += elapsed }
            if kickAt.isFinite { kickAt += elapsed }
            if tackleAt.isFinite { tackleAt += elapsed }
            if remoteKickAt.isFinite { remoteKickAt += elapsed }
            if remoteTackleAt.isFinite { remoteTackleAt += elapsed }
            if feedbackUntil > 0 { feedbackUntil += elapsed }
        }
        paused = value
        if value { pauseStartedAt = ProcessInfo.processInfo.systemUptime }
        if value { keys.removeAll(); velocity = .zero; zHeld = false; zConsumed = false }
        needsDisplay = true
    }

    private var visualNow: TimeInterval {
        paused ? pauseStartedAt : ProcessInfo.processInfo.systemUptime
    }

    func showFeedback(_ message: String) {
        feedback = message
        feedbackUntil = ProcessInfo.processInfo.systemUptime + 1.2
        needsDisplay = true
    }

    func stun() {
        motion.cancelSlide()
        fallStartedAt = ProcessInfo.processInfo.systemUptime
        stunnedUntil = fallStartedAt + fallDuration
        velocity = .zero
        keys.removeAll()
        zHeld = false
        zConsumed = false
        needsDisplay = true
    }

    func stunRemote() {
        remoteFallStartedAt = ProcessInfo.processInfo.systemUptime
        remoteStunnedUntil = remoteFallStartedAt + fallDuration
        needsDisplay = true
    }

    func advance(dt rawDelta: TimeInterval) {
        guard !paused else { needsDisplay = true; return }
        let dt = min(max(rawDelta, 0), 0.05)
        let turning = (0..<turnDuration).contains(ProcessInfo.processInfo.systemUptime - localTurnAt)
        if window?.isKeyWindow != true || ProcessInfo.processInfo.systemUptime < stunnedUntil {
            keys.removeAll(); sprint = false; zHeld = false; zConsumed = false
        }
        let phantom = (0..<phantomDuration).contains(ProcessInfo.processInfo.systemUptime - localPhantomAt)
        let activeSpecial = specialMoves[true].flatMap { specialAnimations[$0.move]?.image(at: visualNow - $0.startedAt) }
        let dx = CGFloat((keys.contains(124) ? 1 : 0) - (keys.contains(123) ? 1 : 0))
        let dy = CGFloat((keys.contains(126) ? 1 : 0) - (keys.contains(125) ? 1 : 0))
        let length = hypot(dx, dy)
        let movement = motion.tick(dt:dt,moving:length > 0,sprint:sprint,
                                  canMove:!isLocalFallen && activeSpecial == nil && !turning && !phantom)
        let speed: CGFloat = movement.sprinting ? 0.48 : 0.33
        let target = movement.slide ?? (activeSpecial != nil ? .zero : phantom ? CGPoint(x: 0, y: phantomVertical * 0.72) :
            turning ? CGPoint(x: localDirection.x * 0.19, y: localDirection.y * 0.19) :
            (length > 0 ? CGPoint(x: dx / length * speed, y: dy / length * speed) : .zero))
        let blend = movement.slide != nil ? 1 : min(CGFloat(1), CGFloat(dt) * 14)
        velocity.x += (target.x - velocity.x) * blend
        velocity.y += (target.y - velocity.y) * blend
        localPosition.x = min(max(localPosition.x + velocity.x * dt, 0.065), 0.935)
        localPosition.y = min(max(localPosition.y + velocity.y * dt, 0.10), 0.90)
        let remoteBlend = min(CGFloat(1), CGFloat(dt) * 12)
        remotePosition.x += (remoteTarget.x - remotePosition.x) * remoteBlend
        remotePosition.y += (remoteTarget.y - remotePosition.y) * remoteBlend
        if length > 0 && !turning && !phantom && movement.slide == nil && activeSpecial == nil {
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
        if event.keyCode == 53 {
            if !event.isARepeat { onPauseToggle?() }
            return
        }
        guard !paused, !isLocalFallen else { return }
        switch event.keyCode {
        case 123, 124, 125, 126: keys.insert(event.keyCode)
        case 2: if !event.isARepeat {
            kickAt = ProcessInfo.processInfo.systemUptime
            if zHeld { zConsumed = true; onCurveShot?(localPosition, localDirection) }
            else { onKick?(localPosition, localDirection) }
        }
        case 49: break
        case 0: if !event.isARepeat {
            onTackle?(localPosition, localDirection)
        }
        case 3: if !event.isARepeat { onPowerShot?(localPosition) }
        case 14: if !event.isARepeat { onStepover?() } // E: SIU's extra skill binding.
        case 12: if !event.isARepeat { onBackheel?() } // Q: backward heel shot.
        case 6: if !event.isARepeat { zHeld = true; zConsumed = false }
        case 1: if !event.isARepeat { onRainbow?() }
        case 7: if !event.isARepeat {
            let vertical: Double = keys.contains(125) ? -1 : (keys.contains(126) ? 1 :
                (localPosition.y < 0.5 ? 1 : -1))
            onPhantom?(vertical)
        }
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 6 {
            if zHeld && !zConsumed && !paused && !isLocalFallen { onMarseille?() }
            zHeld = false
            zConsumed = false
            return
        }
        if keys.contains(event.keyCode) { keys.remove(event.keyCode) }
        else { super.keyUp(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        sprint = event.modifierFlags.contains(.shift)
        super.flagsChanged(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.035, green: 0.18, blue: 0.11, alpha: 1).setFill()
        bounds.fill()
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        let powerElapsed = visualNow - powerStartedAt
        if effectsEnabled && !paused && (0...0.75).contains(powerElapsed), let context {
            let focus = powerFocusLocal ? localPosition : remotePosition
            let zoom = 1 + 0.38 * sin(.pi * CGFloat(powerElapsed / 0.75))
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.scaleBy(x: zoom, y: zoom)
            context.translateBy(x: -bounds.width * focus.x, y: -bounds.height * focus.y)
        }
        drawPitch()
        drawGoals()
        drawPlayer(at: remotePosition, direction: remoteDirection, isLocal: false)
        drawPlayer(at: localPosition, direction: localDirection, isLocal: true)
        drawBall()
        context?.restoreGState()
        drawScoreboard()
        drawControls()
        if paused { drawPauseOverlay() }
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
        if phantomProgress(side: isLocal ? homeSide : (homeSide == .left ? .right : .left)) != nil {
            for index in 1...3 {
                let trail = NSRect(x: center.x - 27, y: center.y - CGFloat(index * 14),
                                   width: 54, height: 14)
                color.withAlphaComponent(0.18 / CGFloat(index)).setFill()
                NSBezierPath(ovalIn: trail).fill()
            }
        }
        let marker = NSBezierPath(ovalIn: NSRect(x: center.x - 32, y: center.y - 20, width: 64, height: 30))
        color.withAlphaComponent(0.27).setFill(); marker.fill()
        marker.lineWidth = 3; color.setStroke(); marker.stroke()
        if !sprites.isEmpty {
            let now = visualNow
            let sinceKick = now - (isLocal ? kickAt : remoteKickAt)
            let sinceTackle = now - (isLocal ? tackleAt : remoteTackleAt)
            let sinceFall = now - (isLocal ? fallStartedAt : remoteFallStartedAt)
            let sinceTurn = now - (isLocal ? localTurnAt : remoteTurnAt)
            let isFalling = (0..<fallDuration).contains(sinceFall)
            let image: NSImage
            let specialImage = specialMoves[isLocal].flatMap { specialAnimations[$0.move]?.image(at: now - $0.startedAt) }
            if isFalling {
                image = sprites[min(2, sprites.count - 1)]
            } else if let specialImage {
                image = specialImage
            } else if sinceKick < 0.55, !kickSprites.isEmpty {
                image = kickSprites[min(kickSprites.count - 1, Int(sinceKick / 0.14))]
            } else if sinceTackle < 0.50, !tackleSprites.isEmpty {
                image = tackleSprites[min(tackleSprites.count - 1, Int(sinceTackle / 0.13))]
            } else {
                let frame = isLocal ? Int(animationPhase) % sprites.count : 2
                image = sprites[frame]
            }
            let height: CGFloat = specialImage != nil && !isFalling ? 154 : 118
            let width = min(specialImage != nil ? 116 : 88, height * image.size.width / max(image.size.height, 1))
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.translateBy(x: center.x, y: center.y - 12)
            if (0..<turnDuration).contains(sinceTurn) {
                let facing = cos(2 * Double.pi * sinceTurn / turnDuration)
                context.scaleBy(x: CGFloat(abs(facing) < 0.16 ? (facing < 0 ? -0.16 : 0.16) : facing), y: 1)
            }
            if direction.x < -0.1 { context.scaleBy(x: -1, y: 1) }
            if !isFalling && (0..<AthleteMotion.slideDuration).contains(sinceTackle) {
                context.rotate(by:-Double.pi/3)
            }
            if isFalling {
                let tilt: CGFloat
                if sinceFall < 0.35 { tilt = CGFloat(sinceFall / 0.35) }
                else if sinceFall < 1.08 { tilt = 1 }
                else { tilt = CGFloat(max(0, 1 - (sinceFall - 1.08) / 0.47)) }
                context.rotate(by: -(.pi / 2) * tilt)
            }
            image.draw(in: NSRect(x: -width / 2, y: 0, width: width, height: height))
            context.restoreGState()
        }
        let fallenUntil = isLocal ? stunnedUntil : remoteStunnedUntil
        if visualNow >= fallenUntil {
            let arrowTip = point(position.x + direction.x * 0.035, position.y + direction.y * 0.052)
            let arrow = NSBezierPath()
            arrow.move(to: center); arrow.line(to: arrowTip)
            arrow.lineWidth = 5; color.setStroke(); arrow.stroke()
        }
        let label = isLocal ? "나" : "상대"
        let stamina = isLocal ? motion.stamina : remoteStamina
        let bar = NSRect(x:center.x-30,y:center.y-61,width:60,height:5)
        NSColor.black.withAlphaComponent(0.5).setFill(); bar.fill()
        (stamina < 20 ? NSColor.systemOrange : NSColor.systemGreen).setFill()
        NSRect(x:bar.minX,y:bar.minY,width:bar.width*stamina/100,height:bar.height).fill()
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
        let lift = CGFloat(ball.z) * bounds.height * 0.72
        let speed = hypot(ball.vx, ball.vy)
        if effectsEnabled, ball.carrier == nil, speed > 0.4 {
            for (index, sample) in ballTrail.enumerated() {
                let alpha = CGFloat(index + 1) / CGFloat(max(1, ballTrail.count)) * 0.13
                NSColor.white.withAlphaComponent(alpha).setFill()
                let raised = sample.0.y + sample.1 * bounds.height * 0.72
                NSBezierPath(ovalIn: NSRect(x: sample.0.x - 7, y: raised - 7, width: 14, height: 14)).fill()
            }
        }
        if fireBall && effectsEnabled {
            let speed = hypot(ball.vx, ball.vy)
            let ux = speed > 0.01 ? ball.vx / speed : 1
            let uy = speed > 0.01 ? ball.vy / speed : 0
            for index in (1...5).reversed() {
                let offset = CGFloat(index * 11)
                let radius = CGFloat(max(5, 18 - index * 2))
                let trail = NSRect(x: center.x - CGFloat(ux) * offset - radius,
                                   y: center.y - CGFloat(uy) * offset - radius,
                                   width: radius * 2, height: radius * 2)
                NSColor(calibratedRed: 1, green: index.isMultiple(of: 2) ? 0.25 : 0.65,
                        blue: 0.02, alpha: 0.68 - CGFloat(index) * 0.09).setFill()
                NSBezierPath(ovalIn: trail).fill()
            }
            NSColor.systemOrange.withAlphaComponent(0.38).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 28, y: center.y - 26,
                                        width: 56, height: 56)).fill()
        }
        let shadowWidth = 30 + min(24, lift * 0.15)
        let shadow = NSBezierPath(ovalIn: NSRect(x: center.x - shadowWidth / 2, y: center.y - 10, width: shadowWidth, height: 10))
        NSColor.black.withAlphaComponent(max(0.12, 0.36 - Double(ball.z) * 0.8)).setFill(); shadow.fill()
        let landing = visualNow - bounceAt
        if effectsEnabled, (0..<0.22).contains(landing) {
            let radius = CGFloat(landing / 0.22) * 24 + 12
            NSColor.white.withAlphaComponent(CGFloat(1 - landing / 0.22) * 0.25).setStroke()
            NSBezierPath(ovalIn: NSRect(x: center.x-radius, y: center.y-radius/3, width:radius*2, height:radius*2/3)).stroke()
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: center.x, y: center.y + lift + 8)
        if (0..<0.12).contains(landing) { context.scaleBy(x: 1.12, y: 0.88) }
        let sphere = NSBezierPath(ovalIn: NSRect(x: -12, y: -12, width: 24, height: 24))
        sphere.addClip()
        NSGradient(starting: .white, ending: NSColor(calibratedWhite: 0.52, alpha: 1))?.draw(in: sphere, angle: -55)
        context.rotate(by: ballRotation)
        for patch in 0..<6 {
            let a = CGFloat(patch) * .pi / 3
            let px: CGFloat = patch == 0 ? 0 : cos(a) * 13
            let py: CGFloat = patch == 0 ? 0 : sin(a) * 13
            let panel = NSBezierPath()
            for corner in 0..<5 {
                let theta = CGFloat(corner) * .pi * 2 / 5 + a
                let p = NSPoint(x: px + cos(theta)*5, y: py + sin(theta)*5)
                if corner == 0 { panel.move(to:p) } else { panel.line(to:p) }
            }
            panel.close()
            NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); panel.fill()
            NSColor(calibratedWhite: 0.30, alpha: 1).setStroke(); panel.lineWidth = 0.5; panel.stroke()
        }
        context.restoreGState()
        NSColor.white.withAlphaComponent(0.42).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x-6, y:center.y+lift+12, width:6,height:4)).fill()
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
            (visualNow < feedbackUntil ? feedback : "")
        if !notice.isEmpty {
            NSString(string: notice).draw(in: NSRect(x: bounds.midX - 240, y: bounds.midY + 125,
                                                     width: 480, height: 54), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 34), .foregroundColor: NSColor.white,
                .paragraphStyle: centeredText
            ])
        }
    }

    private func drawControls() {
        NSString(string: "방향키 이동 · Shift 달리기 · D 슛 · A 태클 · S 사포 · X 팬텀 · Z 턴 · E 발재간 · Q 백숏").draw(
            in: NSRect(x: 0, y: 9, width: bounds.width, height: 20),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                             .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                             .paragraphStyle: centeredText])
    }

    private func drawPauseOverlay() {
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()
        NSString(string: "일시정지").draw(in: NSRect(x: bounds.midX - 150, y: bounds.midY + 150,
                                                   width: 300, height: 55), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 35), .foregroundColor: NSColor.white,
            .paragraphStyle: centeredText
        ])
    }
}
