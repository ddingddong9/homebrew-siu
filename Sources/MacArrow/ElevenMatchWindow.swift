import AppKit
import RealityKit

@MainActor
final class ElevenMatchWindowController: NSWindowController, NSWindowDelegate {
    private var engine = ElevenMatchEngine()
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private let inputView: ElevenInputView
    private let arView: ARView
    private let root = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var playerEntities: [ModelEntity] = []
    private var previousPlayerPositions: [SIMD2<Double>] = []
    private var redAnimationMaterials: [String: [UnlitMaterial]] = [:]
    private var cameraFocusX: Float = 0
    private let ballEntity = ModelEntity(mesh: .generateSphere(radius: 0.034),
                                         materials: [SimpleMaterial(color: .white, isMetallic: false)])
    private let selectedMarker = Entity()
    private let selectedDirection = ModelEntity(mesh: .generateBox(width: 0.09, height: 0.015, depth: 0.09),
                                                 materials: [UnlitMaterial(color: .systemYellow)])
    private let scoreLabel = NSTextField(labelWithString: "")
    private let miniMap = ElevenMiniMapView(frame: NSRect(x: 480, y: 48, width: 220, height: 112))
    var isRunning: Bool { timer != nil }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
        inputView = ElevenInputView(frame: frame)
        arView = ARView(frame: frame)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SIU — 11대11 3D 경기장 (로컬 시제품)"
        window.minSize = NSSize(width: 860, height: 560)
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = inputView
        arView.autoresizingMask = [.width, .height]
        inputView.addSubview(arView)
        inputView.onSwitch = { [weak self] in self?.engine.switchPlayer() }
        inputView.onPass = { [weak self] in self?.engine.pass() }
        inputView.onShoot = { [weak self] curved in self?.engine.shoot(curved: curved) }
        inputView.onTackle = { [weak self] in self?.engine.tackle() }
        inputView.onFeint = { [weak self] in self?.engine.feint() }
        inputView.onPause = { [weak self] in self?.engine.togglePause() }
        setupHUD()
        setupScene()
    }

    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        timer?.invalidate()
        timer = nil
        sender.orderOut(nil)
        return false
    }

    func show() {
        if timer == nil {
            engine = ElevenMatchEngine()
            lastTick = ProcessInfo.processInfo.systemUptime
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(inputView)
        NSApplication.shared.activate(ignoringOtherApps: true)
        render()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }

    private func setupHUD() {
        scoreLabel.alignment = .center
        scoreLabel.textColor = .white
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .bold)
        scoreLabel.wantsLayer = true
        scoreLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        scoreLabel.frame = NSRect(x: 330, y: 700, width: 520, height: 40)
        scoreLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        inputView.addSubview(scoreLabel)
        let help = NSTextField(labelWithString:
            "방향키 이동 · E 질주 · S 패스 · D 슛 · Q 선수 전환 · A 태클 · X 페인트 · Esc 일시정지")
        help.alignment = .center
        help.textColor = .white
        help.font = .systemFont(ofSize: 14, weight: .semibold)
        help.wantsLayer = true
        help.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        help.frame = NSRect(x: 145, y: 14, width: 890, height: 26)
        help.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        inputView.addSubview(help)
        miniMap.wantsLayer = true
        miniMap.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        miniMap.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        inputView.addSubview(miniMap)
    }

    private func setupScene() {
        arView.environment.background = .color(NSColor(calibratedRed: 0.055, green: 0.10,
                                                       blue: 0.16, alpha: 1))
        arView.scene.addAnchor(root)
        let pitch = ModelEntity(mesh: .generatePlane(width: 32, depth: 20),
                                materials: [UnlitMaterial(color: NSColor(calibratedRed: 0.08,
                                                                         green: 0.39, blue: 0.19, alpha: 1))])
        root.addChild(pitch)
        for stripe in 0..<10 where stripe.isMultiple(of: 2) {
            addBox(width: 3.2, height: 0.006, depth: 20,
                   at: SIMD3<Float>(-14.4 + Float(stripe) * 3.2, 0.007, 0),
                   color: NSColor(calibratedRed: 0.10, green: 0.44, blue: 0.21, alpha: 1))
        }
        addLine(x: 0, z: 0, width: 0.05, depth: 20)
        for x: Float in [-16, 16] { addLine(x: x, z: 0, width: 0.07, depth: 20) }
        for z: Float in [-10, 10] { addLine(x: 0, z: z, width: 32, depth: 0.07) }
        for side: Float in [-1, 1] {
            let boxX = side * 13.6
            addLine(x: boxX, z: -5.9, width: 4.8, depth: 0.06)
            addLine(x: boxX, z: 5.9, width: 4.8, depth: 0.06)
            addLine(x: side * 11.2, z: 0, width: 0.06, depth: 11.8)
            addBox(width: 0.045, height: 0.74, depth: 0.045,
                   at: SIMD3<Float>(side * 16, 0.37, -1.12), color: .white)
            addBox(width: 0.045, height: 0.74, depth: 0.045,
                   at: SIMD3<Float>(side * 16, 0.37, 1.12), color: .white)
            addBox(width: 0.045, height: 0.045, depth: 2.24,
                   at: SIMD3<Float>(side * 16, 0.74, 0), color: .white)
        }
        // A segmented center circle remains flat on the 3D pitch.
        for index in 0..<36 {
            let angle = Float(index) * .pi * 2 / 36
            let segment = ModelEntity(mesh: .generateBox(width: 0.48, height: 0.018, depth: 0.055),
                                      materials: [UnlitMaterial(color: .white)])
            segment.position = SIMD3<Float>(cos(angle) * 2.79, 0.02, sin(angle) * 2.79)
            segment.orientation = simd_quatf(angle: -angle - .pi / 2, axis: SIMD3<Float>(0, 1, 0))
            root.addChild(segment)
        }
        // Low stadium walls give the camera a real depth cue rather than a flat backdrop.
        for z: Float in [-11.3, 11.3] {
            addBox(width: 36, height: 1.0, depth: 0.5,
                   at: SIMD3<Float>(0, 0.5, z), color: NSColor(calibratedRed: 0.06,
                                                               green: 0.14, blue: 0.20, alpha: 1))
        }
        root.addChild(ballEntity)
        root.addChild(selectedMarker)
        for index in 0..<24 {
            let angle = Float(index) * .pi * 2 / 24
            let piece = ModelEntity(mesh: .generateBox(width: 0.07, height: 0.015, depth: 0.025),
                                    materials: [UnlitMaterial(color: .systemYellow)])
            piece.position = SIMD3<Float>(cos(angle) * 0.24, 0, sin(angle) * 0.24)
            piece.orientation = simd_quatf(angle: -angle - .pi / 2, axis: SIMD3<Float>(0, 1, 0))
            selectedMarker.addChild(piece)
        }
        selectedMarker.addChild(selectedDirection)
        root.addChild(camera)
        loadPlayers()
        render()
    }

    private func addLine(x: Float, z: Float, width: Float, depth: Float) {
        addBox(width: width, height: 0.02, depth: depth,
               at: SIMD3<Float>(x, 0.025, z), color: .white)
    }

    private func addBox(width: Float, height: Float, depth: Float,
                        at position: SIMD3<Float>, color: NSColor) {
        let entity = ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth),
                                 materials: [UnlitMaterial(color: color)])
        entity.position = position
        root.addChild(entity)
    }

    private func loadPlayers() {
        for (name, count) in [("move", 4), ("run", 4), ("run-front", 4),
                              ("run-back", 4), ("kick", 8), ("kick-front", 4),
                              ("kick-side", 4), ("tackle", 4),
                              ("tackle-front", 4), ("tackle-back", 4)] {
            redAnimationMaterials[name] = (1...count).compactMap { index in
                let filename = String(format: "%@-%02d", name, index)
                guard let url = ResourceBundle.images.url(forResource: filename, withExtension: "png"),
                      let texture = try? TextureResource.load(contentsOf: url) else { return nil }
                var material = UnlitMaterial()
                material.color = .init(texture: .init(texture))
                material.opacityThreshold = 0.08
                return material
            }
        }
        let redTexture = ResourceBundle.images.url(forResource: "move-01", withExtension: "png")
            .flatMap { try? TextureResource.load(contentsOf: $0) }
        let blueTexture = ResourceBundle.images.url(forResource: "blue-player", withExtension: "png")
            .flatMap { try? TextureResource.load(contentsOf: $0) }
        for player in engine.players {
            let texture = player.side == .left ? redTexture : blueTexture
            let material: UnlitMaterial
            if let texture {
                var transparent = UnlitMaterial()
                transparent.color = .init(texture: .init(texture))
                transparent.opacityThreshold = 0.08
                material = transparent
            } else {
                material = UnlitMaterial(color: player.side == .left ? .systemRed : .systemBlue)
            }
            let sprite = ModelEntity(mesh: .generatePlane(width: 0.30, height: 0.55),
                                     materials: [material])
            root.addChild(sprite)
            playerEntities.append(sprite)
            previousPlayerPositions.append(SIMD2<Double>(player.x, player.y))
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick
        lastTick = now
        engine.step(input: inputView.currentInput, dt: dt)
        render()
    }

    private func render() {
        let now = ProcessInfo.processInfo.systemUptime
        for player in engine.players {
            let x = Float((player.x - 0.5) * 32)
            let z = Float((player.y - 0.5) * 20)
            let fallen = player.fallenFor > 0
            let previous = previousPlayerPositions[player.id]
            let moving = hypot(player.x - previous.x, player.y - previous.y) > 0.00003
            previousPlayerPositions[player.id] = SIMD2<Double>(player.x, player.y)
            let bob = moving && !fallen ? Float(sin(now * 26) * 0.012) : 0
            playerEntities[player.id].position = SIMD3<Float>(x, (fallen ? 0.10 : 0.28) + bob, z)
            let actionTilt: Float = player.side == .right && player.tackleFor > 0 ? 0.45 :
                (player.feintFor > 0 ? Float(player.feintLean) * 0.17 : 0)
            playerEntities[player.id].orientation = simd_quatf(angle: fallen ? .pi / 2 : actionTilt,
                                                                axis: SIMD3<Float>(0, 0, 1))
            if player.side == .left {
                let category: String
                let frame: Int
                if player.tackleFor > 0 {
                    category = player.facingY > 0.35 ? "tackle-front" :
                        (player.facingY < -0.35 ? "tackle-back" : "tackle")
                    frame = Int((0.36 - player.tackleFor) / 0.36 * 4)
                } else if player.kickFor > 0 {
                    category = player.facingY > 0.35 ? "kick-front" :
                        (abs(player.facingY) < 0.35 ? "kick-side" : "kick")
                    frame = Int((0.38 - player.kickFor) / 0.38 *
                                Double(redAnimationMaterials[category]?.count ?? 4))
                } else if moving || player.feintFor > 0 {
                    category = player.facingY > 0.35 ? "run-front" :
                        (player.facingY < -0.35 ? "run-back" : "run")
                    frame = Int(now * 10) % 4
                } else {
                    category = "move"
                    frame = 0
                }
                if let materials = redAnimationMaterials[category], !materials.isEmpty {
                    playerEntities[player.id].model?.materials = [materials[min(max(frame, 0), materials.count - 1)]]
                }
            }
        }
        let ballX = Float((engine.ball.x - 0.5) * 32)
        let ballZ = Float((engine.ball.y - 0.5) * 20)
        ballEntity.position = SIMD3<Float>(ballX, 0.04 + Float(engine.ball.z) * 9, ballZ)
        let selected = engine.selected
        selectedMarker.position = SIMD3<Float>(Float((selected.x - 0.5) * 32), 0.04,
                                                Float((selected.y - 0.5) * 20))
        selectedDirection.position = SIMD3<Float>(Float(selected.facingX) * 0.34, 0,
                                                   Float(selected.facingY) * 0.34)
        let desiredFocusX = min(max(ballX * 0.82, -11), 11)
        cameraFocusX += (desiredFocusX - cameraFocusX) * 0.10
        let from = SIMD3<Float>(cameraFocusX, 7.5, 10.5)
        camera.look(at: SIMD3<Float>(cameraFocusX, 0, 0), from: from, relativeTo: root)
        miniMap.players = engine.players
        miniMap.ball = engine.ball
        miniMap.selectedID = engine.selectedID
        miniMap.needsDisplay = true
        let minutes = Int(engine.remaining) / 60
        let seconds = Int(engine.remaining) % 60
        let state = engine.paused ? "  일시정지" : (engine.finished ? "  종료" : "")
        scoreLabel.stringValue = "빨강  \(engine.leftScore) : \(engine.rightScore)  파랑    " +
            String(format: "%02d:%02d", minutes, seconds) + state
    }
}

@MainActor
private final class ElevenInputView: NSView {
    var onSwitch: (() -> Void)?
    var onPass: (() -> Void)?
    var onShoot: ((Bool) -> Void)?
    var onTackle: (() -> Void)?
    var onFeint: (() -> Void)?
    var onPause: (() -> Void)?
    private var pressed = Set<UInt16>()
    private var zHeld = false

    override var acceptsFirstResponder: Bool { true }

    var currentInput: ElevenInput {
        ElevenInput(horizontal: Double((pressed.contains(124) ? 1 : 0) -
                                       (pressed.contains(123) ? 1 : 0)),
                    vertical: Double((pressed.contains(126) ? 1 : 0) -
                                     (pressed.contains(125) ? 1 : 0)),
                    sprint: pressed.contains(14))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124, 125, 126, 14: pressed.insert(event.keyCode)
        case 12: if !event.isARepeat { onSwitch?() } // Q
        case 1: if !event.isARepeat { onPass?() } // S
        case 2: if !event.isARepeat {
            onShoot?(zHeld)
        } // D; Z+D is intentionally absent from the on-screen hint.
        case 0: if !event.isARepeat { onTackle?() } // A
        case 7: if !event.isARepeat { onFeint?() } // X
        case 6: if !event.isARepeat { zHeld = true }
        case 53: if !event.isARepeat { onPause?(); pressed.removeAll() }
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 6 { zHeld = false; return }
        if pressed.contains(event.keyCode) { pressed.remove(event.keyCode) }
        else { super.keyUp(with: event) }
    }
}

@MainActor
private final class ElevenMiniMapView: NSView {
    var players: [ElevenPlayer] = []
    var ball = ArenaBall.kickoff
    var selectedID = 9

    override func draw(_ dirtyRect: NSRect) {
        let field = bounds.insetBy(dx: 9, dy: 8)
        NSColor(calibratedRed: 0.08, green: 0.29, blue: 0.16, alpha: 0.9).setFill()
        field.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        let outline = NSBezierPath(rect: field)
        outline.lineWidth = 0.8
        outline.stroke()
        let middle = NSBezierPath()
        middle.move(to: CGPoint(x: field.midX, y: field.minY))
        middle.line(to: CGPoint(x: field.midX, y: field.maxY))
        middle.lineWidth = 0.8
        middle.stroke()
        for player in players {
            let point = CGPoint(x: field.minX + field.width * player.x,
                                y: field.minY + field.height * (1 - player.y))
            (player.side == .left ? NSColor.systemRed : NSColor.systemCyan).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5,
                                       width: 5, height: 5)).fill()
            if player.id == selectedID {
                NSColor.systemYellow.setStroke()
                let marker = NSBezierPath(ovalIn: NSRect(x: point.x - 5, y: point.y - 5,
                                                         width: 10, height: 10))
                marker.lineWidth = 1.4
                marker.stroke()
            }
        }
        let ballPoint = CGPoint(x: field.minX + field.width * ball.x,
                                y: field.minY + field.height * (1 - ball.y))
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: ballPoint.x - 3, y: ballPoint.y - 3,
                                   width: 6, height: 6)).fill()
    }
}
