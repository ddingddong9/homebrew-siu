import AppKit
import RealityKit

@MainActor
final class ElevenMatchWindowController: NSWindowController, NSWindowDelegate {
    private var engine = ElevenMatchEngine()
    private let session = ElevenSession()
    private var timer: Timer?
    private var lastTick = 0.0, networkClock = 0.0, lastSnapshot = 0.0
    private var matchDuration = 300.0
    private let inputView: ElevenInputView
    private let arView: ARView
    private let root = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var playerEntities: [ModelEntity] = [], shadows: [ModelEntity] = []
    private var spriteFrames: [String: [SpriteFrame]] = [:]
    private var cameraFocus = SIMD2<Float>(0, 0)
    private var resetCamera = true
    private let ballEntity = ModelEntity(mesh: .generateSphere(radius: 0.11),
                                         materials: [SimpleMaterial(color: .white, isMetallic: false)])
    private let ballShadow = ModelEntity(mesh: .generatePlane(width: 0.3, depth: 0.3),
                                         materials: [UnlitMaterial(color: .black)])
    private let selectedMarker = Entity()
    private let selectedDirection = ModelEntity(mesh: .generateBox(width: 0.16, height: 0.03, depth: 0.38),
                                                 materials: [UnlitMaterial(color: .systemYellow)])
    private let scoreLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let roomPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let homeView = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 760))
    private var showingHome = true
    private let miniMap = ElevenMiniMapView(frame: NSRect(x: 480, y: 50, width: 220, height: 136))
    var isRunning: Bool { timer != nil }
    private struct SpriteFrame {
        var material: UnlitMaterial
        var mesh: MeshResource
        var mirror: MeshResource
        var height: Float
    }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
        inputView = ElevenInputView(frame: frame)
        arView = ARView(frame: frame)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SIU — 11대11 · 개발 미리보기"
        window.minSize = NSSize(width: 980, height: 650)
        window.center()
        super.init(window: window)
        window.delegate = self; window.contentView = inputView
        arView.autoresizingMask = [.width, .height]; inputView.addSubview(arView)
        inputView.onCommand = { [weak self] command, power in self?.command(command, power: power) }
        inputView.isDefending = { [weak self] in
            guard let self else { return false }
            return self.engine.ball.carrier != (self.session.role == .guest ? ElevenSide.right : .left)
        }
        inputView.onPause = { [weak self] in self?.pauseSettings() }
        session.onStatus = { [weak self] in self?.updateStatus() }
        session.onSnapshot = { [weak self] state in
            guard let self else { return }
            if state.kickoffFor > 0 && self.engine.kickoffFor == 0 { self.resetCamera = true }
            self.engine.apply(state); self.lastSnapshot = ProcessInfo.processInfo.systemUptime
            if !state.paused && self.showingHome { self.showGame() }
        }
        session.onCommand = { [weak self] command, power in self?.applyCommand(command, side: .right, power: power) }
        session.onConnected = { [weak self] in self?.engine.remoteControlled = true }
        session.onDisconnect = { [weak self] in
            guard let self else { return }
            self.inputView.clear()
            if !self.engine.paused { self.engine.togglePause() }
        }
        session.approve = { [weak self] peer in
            let alert = NSAlert()
            alert.messageText = "친구의 참가 요청"
            alert.informativeText = "접속 기기: \(peer)\n신뢰하는 친구의 요청만 허용하세요."
            alert.addButton(withTitle: "허용"); alert.addButton(withTitle: "거절")
            let accepted = alert.runModal() == .alertFirstButtonReturn
            self?.lastTick = ProcessInfo.processInfo.systemUptime
            self?.restoreKeyboard()
            return accepted
        }
        setupHUD(); setupScene()
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidResignKey(_ notification: Notification) {
        inputView.clear()
        if session.role == .guest { session.sendInput(ElevenInput()); session.sendCommand(.pause) }
        else if !engine.paused { engine.togglePause() }
    }
    func show() {
        if timer == nil {
            engine = ElevenMatchEngine(duration: matchDuration); resetCamera = true
            engine.togglePause()
            lastTick = ProcessInfo.processInfo.systemUptime
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        window?.makeKeyAndOrderFront(nil); restoreKeyboard()
        NSApplication.shared.activate(ignoringOtherApps: true)
        render(dt: 0)
    }
    func hide() {
        timer?.invalidate(); timer = nil; session.stop(); inputView.clear(); window?.orderOut(nil)
    }
    private func restoreKeyboard() { window?.makeFirstResponder(inputView) }
    private func showGame() {
        showingHome = false; homeView.isHidden = true; arView.isHidden = false
        inputView.clear(); restoreKeyboard()
    }
    private func showHome() {
        showingHome = true; homeView.isHidden = false; arView.isHidden = true
        inputView.clear(); restoreKeyboard()
    }
    private func setupHUD() {
        homeView.autoresizingMask = [.width, .height]
        homeView.wantsLayer = true
        homeView.layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.085, blue: 0.09, alpha: 1).cgColor
        let title = NSTextField(labelWithString: "SIU  /  ELEVEN")
        title.font = .systemFont(ofSize: 48, weight: .heavy); title.textColor = .white
        title.frame = NSRect(x: 280, y: 555, width: 680, height: 64)
        title.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        homeView.addSubview(title)
        let subtitle = NSTextField(labelWithString: "11대11 아케이드 축구 · 같은 와이파이에서 친구와 한 팀씩")
        subtitle.textColor = .lightGray; subtitle.font = .systemFont(ofSize: 17, weight: .medium)
        subtitle.frame = NSRect(x: 280, y: 510, width: 720, height: 28)
        subtitle.autoresizingMask = title.autoresizingMask; homeView.addSubview(subtitle)
        scoreLabel.alignment = .center; scoreLabel.textColor = .white
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 23, weight: .bold)
        scoreLabel.wantsLayer = true; scoreLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        scoreLabel.frame = NSRect(x: 330, y: 698, width: 520, height: 36)
        scoreLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        inputView.addSubview(scoreLabel)
        let controls: [(String, Selector)] = [
            ("로컬 연습", #selector(solo)), ("방 만들기", #selector(host)),
            ("방 검색", #selector(browse)), ("참가", #selector(join)),
            ("경기 시작", #selector(startMatch)), ("나가기", #selector(leave))
        ]
        for (i, item) in controls.enumerated() {
            let button = NSButton(title: item.0, target: self, action: item.1)
            button.frame = NSRect(x: 280 + (i % 3) * 210, y: 420 - (i / 3) * 68, width: 190, height: 48)
            button.autoresizingMask = title.autoresizingMask; homeView.addSubview(button)
        }
        roomPicker.frame = NSRect(x: 280, y: 290, width: 610, height: 30)
        roomPicker.autoresizingMask = title.autoresizingMask; homeView.addSubview(roomPicker)
        statusLabel.frame = NSRect(x: 280, y: 240, width: 790, height: 30)
        statusLabel.autoresizingMask = title.autoresizingMask; statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        homeView.addSubview(statusLabel)
        let instructions = NSTextField(wrappingLabelWithString: "방장: 방 만들기 → 친구 참가 허용 → 경기 시작\n친구: 방 검색 → 목록에서 선택 → 참가\n처음 연결할 때 macOS의 로컬 네트워크 접근을 허용해 주세요.\n서로 다른 와이파이·게스트 와이파이에서는 연결되지 않을 수 있습니다.")
        instructions.textColor = .lightGray; instructions.font = .systemFont(ofSize: 14)
        instructions.frame = NSRect(x: 280, y: 110, width: 660, height: 105)
        instructions.autoresizingMask = title.autoresizingMask; homeView.addSubview(instructions)
        let help = NSTextField(labelWithString:
            "방향키 이동 · E 질주 · S 패스 · D 슛/스탠딩 · A 크로스/슬라이딩 · Q 전환 · Shift+Z/X/C 개인기 · Esc 정지")
        help.alignment = .center; help.textColor = .white; help.font = .systemFont(ofSize: 14, weight: .semibold)
        help.wantsLayer = true; help.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        help.frame = NSRect(x: 120, y: 15, width: 940, height: 26)
        help.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]; inputView.addSubview(help)
        miniMap.wantsLayer = true; miniMap.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        miniMap.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]; inputView.addSubview(miniMap)
        inputView.addSubview(homeView); arView.isHidden = true
        updateStatus()
    }
    private func updateStatus() {
        statusLabel.stringValue = session.status
        let selectedName = roomPicker.titleOfSelectedItem
        roomPicker.removeAllItems()
        roomPicker.addItems(withTitles: session.rooms.map(\.name))
        if let selectedName { roomPicker.selectItem(withTitle: selectedName) }
    }
    @objc private func solo() {
        session.stop(); engine = ElevenMatchEngine(duration: matchDuration)
        resetCamera = true; inputView.clear(); restoreKeyboard()
        showGame()
    }
    @objc private func host() {
        let alert = NSAlert(); alert.messageText = "11대11 방 만들기"
        alert.informativeText = "같은 와이파이의 친구에게 이 방이 표시됩니다."
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 64))
        let name = NSTextField(string: "\(Host.current().localizedName ?? "SIU")의 방")
        name.frame = NSRect(x: 0, y: 35, width: 300, height: 24); view.addSubview(name)
        let duration = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        duration.addItems(withTitles: ["3분 경기", "5분 경기", "10분 경기"]); duration.selectItem(at: 1)
        view.addSubview(duration); alert.accessoryView = view
        alert.addButton(withTitle: "방 만들기"); alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn {
            matchDuration = [180.0, 300, 600][duration.indexOfSelectedItem]
            engine = ElevenMatchEngine(duration: matchDuration); engine.togglePause()
            do { try session.host(name: name.stringValue.isEmpty ? "SIU 방" : name.stringValue) }
            catch { statusLabel.stringValue = "방 생성 실패: \(error.localizedDescription)" }
            resetCamera = true
        }
        lastTick = ProcessInfo.processInfo.systemUptime; restoreKeyboard()
    }
    @objc private func browse() {
        session.browse()
        if !engine.paused { engine.togglePause() }
        restoreKeyboard()
    }
    @objc private func join() {
        let i = roomPicker.indexOfSelectedItem
        guard session.rooms.indices.contains(i) else { return }
        engine = ElevenMatchEngine(duration: matchDuration); engine.togglePause()
        session.join(session.rooms[i]); resetCamera = true; restoreKeyboard()
    }
    @objc private func startMatch() {
        guard session.role != .guest, session.role != .host || session.connected else { restoreKeyboard(); return }
        if engine.finished {
            engine = ElevenMatchEngine(duration: matchDuration)
            engine.remoteControlled = session.role == .host
            resetCamera = true
        } else if engine.paused { engine.togglePause() }
        inputView.clear(); restoreKeyboard()
        showGame()
    }
    @objc private func leave() {
        session.stop()
        if !engine.paused { engine.togglePause() }
        inputView.clear(); restoreKeyboard()
        showHome()
    }
    private func command(_ command: ElevenCommand, power: Double = 0.45) {
        guard !showingHome || command == .pause else { return }
        if session.role == .guest { session.sendCommand(command, power: power) }
        else { applyCommand(command, side: .left, power: power) }
    }
    private func applyCommand(_ command: ElevenCommand, side: ElevenSide, power: Double = 0.45) {
        switch command {
        case .pass:
            if engine.ball.carrier != side { engine.switchPlayer(side: side) }
            else { engine.pass(side: side, power: power) }
        case .shot:
            if engine.hasPossession(side) { engine.shoot(side: side, power: power) }
            else { engine.tackle(side: side, sliding: false) }
        case .curve: engine.shoot(curved: true, side: side, power: power)
        case .cross:
            if engine.hasPossession(side) { engine.cross(side: side, power: power) }
            else { engine.tackle(side: side) }
        case .tackle: engine.tackle(side: side)
        case .standing: engine.tackle(side: side, sliding: false)
        case .feint: engine.feint(side: side)
        case .roulette: engine.skill(.roulette, side: side)
        case .rainbow: engine.skill(.rainbow, side: side)
        case .switchPlayer: engine.switchPlayer(side: side)
        case .pause: if !engine.paused { engine.togglePause() }
        case .resume:
            if engine.paused && (session.role != .host || session.connected) { engine.togglePause() }
        }
    }
    private func pauseSettings() {
        command(.pause); inputView.clear()
        let alert = NSAlert(); alert.messageText = "경기 일시정지"
        alert.informativeText = "시간 \(Int(matchDuration / 60))분 · 방향키 이동 · E 질주\n공격: S 패스 · D 슛 · A 크로스 (길게 누르면 강하게)\n수비: D 스탠딩 · A 슬라이딩 · Q 선수 전환\nShift+Z 마르세유턴 · Shift+X 팬텀 · Shift+C 사포\n골키퍼/스로인: S 또는 A로 던지기\n\(session.status)"
        alert.addButton(withTitle: "계속하기"); alert.addButton(withTitle: "경기 나가기")
        // Sheet keeps the main loop/network heartbeat running while settings are open.
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            if result == .alertFirstButtonReturn { self.command(.resume) } else { self.leave() }
            self.lastTick = ProcessInfo.processInfo.systemUptime; self.restoreKeyboard()
        }
    }
    private func setupScene() {
        arView.environment.background = .color(NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.12, alpha: 1))
        arView.scene.addAnchor(root)
        let pitch = ModelEntity(mesh: .generatePlane(width: 116, depth: 78),
            materials: [UnlitMaterial(color: NSColor(calibratedRed: 0.075, green: 0.32, blue: 0.15, alpha: 1))])
        root.addChild(pitch)
        for stripe in 0..<10 {
            box(10.5, 0.006, 68, SIMD3<Float>(-47.25 + Float(stripe) * 10.5, 0.007, 0),
                stripe.isMultiple(of: 2) ? NSColor(calibratedRed: 0.11, green: 0.43, blue: 0.20, alpha: 1) :
                    NSColor(calibratedRed: 0.09, green: 0.38, blue: 0.17, alpha: 1))
        }
        line(0, 0, 0.12, 68)
        for x: Float in [-52.5, 52.5] { line(x, 0, 0.12, 68) }
        for z: Float in [-34, 34] { line(0, z, 105, 0.12) }
        for side: Float in [-1, 1] {
            for (depth, halfWidth): (Float, Float) in [(16.5, 20.16), (5.5, 9.16)] {
                line(side * (52.5 - depth / 2), -halfWidth, depth, 0.12)
                line(side * (52.5 - depth / 2), halfWidth, depth, 0.12)
                line(side * (52.5 - depth), 0, 0.12, halfWidth * 2)
            }
            for z: Float in [-3.66, 3.66] {
                box(0.12, 2.44, 0.12, SIMD3<Float>(side * 52.5, 1.22, z), .white)
                line(side * 53.5, z, 2, 0.06)
            }
            box(0.12, 0.12, 7.32, SIMD3<Float>(side * 52.5, 2.44, 0), .white)
            for n in 0...14 {
                box(0.035, 2.44, 0.035, SIMD3<Float>(side * 54.5, 1.22, -3.66 + Float(n) * 7.32 / 14),
                    NSColor.white.withAlphaComponent(0.45))
            }
            for n in 0...5 {
                box(0.035, 0.035, 7.32, SIMD3<Float>(side * 54.5, Float(n) * 2.44 / 5, 0),
                    NSColor.white.withAlphaComponent(0.45))
            }
        }
        for i in 0..<72 {
            let a = Float(i) * .pi * 2 / 72
            let piece = ModelEntity(mesh: .generateBox(width: 0.80, height: 0.02, depth: 0.12),
                                    materials: [UnlitMaterial(color: .white)])
            piece.position = SIMD3<Float>(cos(a) * 9.15, 0.03, sin(a) * 9.15)
            piece.orientation = simd_quatf(angle: -a - .pi / 2, axis: SIMD3<Float>(0, 1, 0)); root.addChild(piece)
        }
        root.addChild(ballEntity); root.addChild(ballShadow); root.addChild(selectedMarker)
        // Visible black panels rotate with the ball.
        for axis in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)] {
            for sign: Float in [-1, 1] {
                let patch = ModelEntity(mesh: .generateSphere(radius: 0.035),
                                        materials: [UnlitMaterial(color: .black)])
                patch.position = axis * 0.096 * sign; ballEntity.addChild(patch)
            }
        }
        for i in 0..<32 {
            let a = Float(i) * .pi * 2 / 32
            let piece = ModelEntity(mesh: .generateBox(width: 0.14, height: 0.02, depth: 0.05),
                                    materials: [UnlitMaterial(color: .systemYellow)])
            piece.position = SIMD3<Float>(cos(a) * 0.75, 0, sin(a) * 0.75)
            piece.orientation = simd_quatf(angle: -a - .pi / 2, axis: SIMD3<Float>(0, 1, 0)); selectedMarker.addChild(piece)
        }
        selectedMarker.addChild(selectedDirection); root.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 48
        loadPlayers(); render(dt: 0)
    }
    private func line(_ x: Float, _ z: Float, _ width: Float, _ depth: Float) {
        box(width, 0.02, depth, SIMD3<Float>(x, 0.025, z), .white)
    }
    private func box(_ width: Float, _ height: Float, _ depth: Float, _ position: SIMD3<Float>, _ color: NSColor) {
        let entity = ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth),
                                 materials: [UnlitMaterial(color: color)])
        entity.position = position; root.addChild(entity)
    }
    private func spriteMesh(width: Float, height: Float, mirrored: Bool) throws -> MeshResource {
        var descriptor = MeshDescriptor()
        descriptor.positions = .init([[-width / 2, 0, 0], [width / 2, 0, 0],
                                       [width / 2, height, 0], [-width / 2, height, 0]])
        descriptor.normals = .init(Array(repeating: [0, 0, 1], count: 4))
        let l: Float = mirrored ? 1 : 0, r: Float = mirrored ? 0 : 1
        descriptor.textureCoordinates = .init([[l, 0], [r, 0], [r, 1], [l, 1]])
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try MeshResource.generate(from: [descriptor])
    }
    private func loadPlayers() {
        for (name, count) in [("move", 4), ("run", 4), ("run-front", 4), ("run-back", 4),
                              ("kick", 8), ("kick-front", 4), ("kick-side", 4),
                              ("tackle", 4), ("tackle-front", 4), ("tackle-back", 4)] {
            for blue in [false, true] {
                let images = (1...count).compactMap { i -> CGImage? in
                    guard let url = ResourceBundle.images.url(forResource: String(format: "%@-%02d", name, i),
                                                               withExtension: "png"),
                          let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                    return spriteImage(source, blue: blue)
                }
                let referenceHeight = Float(images.map(\.height).max() ?? 1)
                spriteFrames[(blue ? "blue-" : "red-") + name] = images.compactMap { image in
                    let height = Float(image.height) / referenceHeight * 1.8
                    let width = Float(image.width) / referenceHeight * 1.8
                    guard let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)),
                          let mesh = try? spriteMesh(width: width, height: height, mirrored: false),
                          let mirror = try? spriteMesh(width: width, height: height, mirrored: true) else { return nil }
                    var material = UnlitMaterial()
                    material.color = .init(texture: .init(texture)); material.opacityThreshold = 0.08
                    return SpriteFrame(material: material, mesh: mesh, mirror: mirror, height: height)
                }
            }
        }
        loadKeeperAndThrowSprites()
        for p in engine.players {
            let sprite = ModelEntity(mesh: .generatePlane(width: 0.9, height: 1.8),
                                     materials: [UnlitMaterial(color: p.side == .left ? .red : .blue)])
            root.addChild(sprite); playerEntities.append(sprite)
            let shadow = ModelEntity(mesh: .generatePlane(width: 0.65, depth: 0.35),
                                     materials: [UnlitMaterial(color: NSColor(calibratedWhite: 0.08, alpha: 0.65))])
            root.addChild(shadow); shadows.append(shadow)
        }
    }
    private func loadKeeperAndThrowSprites() {
        guard let url = ResourceBundle.images.url(forResource: "keeper-throw-atlas", withExtension: "png"),
              let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        // Hand-authored atlas regions: the wide dive uses a wider cell, preserving body scale.
        let regions: [(String, [CGRect])] = [
            ("keeper", [CGRect(x: 0, y: 0, width: 360, height: 400), CGRect(x: 360, y: 0, width: 360, height: 400),
                        CGRect(x: 720, y: 0, width: 360, height: 400), CGRect(x: 1080, y: 0, width: 368, height: 400)]),
            ("dive", [CGRect(x: 0, y: 400, width: 305, height: 287), CGRect(x: 305, y: 400, width: 425, height: 275),
                      CGRect(x: 713, y: 540, width: 430, height: 134), CGRect(x: 1143, y: 400, width: 305, height: 287)]),
            ("throw-in", [CGRect(x: 0, y: 688, width: 360, height: 398), CGRect(x: 360, y: 688, width: 360, height: 398),
                          CGRect(x: 720, y: 675, width: 360, height: 411), CGRect(x: 1080, y: 688, width: 368, height: 398)])
        ]
        for (category, regions) in regions {
            for blue in [false, true] {
                spriteFrames[(blue ? "blue-" : "red-") + category] = regions.compactMap { region in
                    guard let cell = source.cropping(to: region), let image = spriteImage(cell, blue: blue),
                          let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) else { return nil }
                    let height = Float(image.height) / 380 * 1.8, width = Float(image.width) / 380 * 1.8
                    guard let mesh = try? spriteMesh(width: width, height: height, mirrored: false),
                          let mirror = try? spriteMesh(width: width, height: height, mirrored: true) else { return nil }
                    var material = UnlitMaterial()
                    material.color = .init(texture: .init(texture)); material.opacityThreshold = 0.08
                    return SpriteFrame(material: material, mesh: mesh, mirror: mirror, height: height)
                }
            }
        }
    }
    /// Runtime team palette only. Source assets remain unchanged; skin/white kit
    /// pixels are excluded by red chroma rather than tinting the entire image.
    private func spriteImage(_ image: CGImage, blue: Bool) -> CGImage? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            guard bytes[i + 3] > 20 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
            if blue && r > g * 1.7 && r > b * 1.6 && r > 35 {
                bytes[i] = UInt8(min(255, b * 0.7))
                bytes[i + 1] = UInt8(min(255, max(g, r * 0.32)))
                bytes[i + 2] = UInt8(min(255, r))
            } else if blue && g > r * 1.35 && g > b * 1.25 && g > 35 {
                // The visiting keeper wears gold; both keepers differ from outfield kits.
                bytes[i] = UInt8(min(255, g * 1.3)); bytes[i + 1] = UInt8(min(255, g))
                bytes[i + 2] = UInt8(min(255, b * 0.4))
            }
        } }
        guard minX <= maxX, minY <= maxY else { return nil }
        return context.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime, dt = now - lastTick
        lastTick = now
        session.checkTimeout(now: now)
        if dt > 0.5 {
            inputView.clear()
            command(.pause)
        }
        if session.role != .guest {
            let wasRestart = engine.kickoffFor > 0
            engine.step(input: inputView.currentInput, dt: min(dt, 0.5), remoteInput: session.remoteInput)
            if !wasRestart && engine.kickoffFor > 0 { resetCamera = true }
        }
        networkClock += dt
        if networkClock >= 0.05 {
            networkClock = 0
            if session.role == .host { session.sendSnapshot(engine.snapshot) }
            if session.role == .guest { session.sendInput(inputView.currentInput) }
        }
        render(dt: min(dt, 0.05))
    }
    private func render(dt: Double) {
        let alpha = session.role == .guest ? min(1, max(0, (ProcessInfo.processInfo.systemUptime - lastSnapshot) / 0.05)) : engine.interpolation
        func blend(_ a: Double, _ b: Double) -> Float { Float(a + (b - a) * alpha) }
        for p in engine.players {
            let previous = engine.previousPlayers.indices.contains(p.id) ? engine.previousPlayers[p.id] : p
            let x = blend(previous.x, p.x) - 52.5, z = blend(previous.y, p.y) - 34
            let sprite = playerEntities[p.id]
            sprite.position = SIMD3<Float>(x, 0.035, z)
            shadows[p.id].position = SIMD3<Float>(x, 0.035, z)
            var category = "move", frame = 0
            if let a = p.action {
                switch a.kind {
                case .pass, .shot, .cross, .standing, .rainbow:
                    category = p.facingY > 0.4 ? "kick-front" : (p.facingY < -0.4 ? "kick" : "kick-side")
                    let n = category == "kick" ? 8 : 4
                    // The authored contact frame is reached at the simulation's contact time.
                    let progress = a.elapsed <= a.contactTime ? a.elapsed / a.contactTime * 0.5 :
                        0.5 + (a.elapsed - a.contactTime) / (a.duration - a.contactTime) * 0.5
                    frame = min(n - 1, Int(progress * Double(n)))
                case .tackle:
                    category = p.facingY > 0.4 ? "tackle-front" : (p.facingY < -0.4 ? "tackle-back" : "tackle")
                    frame = min(3, Int(a.elapsed / a.duration * 4))
                case .feint, .roulette: category = "run"; frame = Int(p.gait * 4) % 4
                case .keeperThrow: category = "keeper"; frame = a.elapsed < a.contactTime ? 2 : 3
                case .throwIn: category = "throw-in"; frame = min(3, Int(a.elapsed / a.duration * 4))
                case .dive: category = "dive"; frame = min(3, Int(a.elapsed / a.duration * 4))
                }
            } else if p.speed > 0.15 {
                category = p.facingY > 0.4 ? "run-front" : (p.facingY < -0.4 ? "run-back" : "run")
                frame = Int(p.gait * 4) % 4
            } else if abs(p.facingY) > 0.4 {
                category = p.facingY > 0 ? "run-front" : "run-back"
            } else { category = "run" }
            if engine.ball.heldBy == p.id && p.action == nil {
                category = engine.ball.throwIn ? "throw-in" : "keeper"; frame = engine.ball.throwIn ? 0 : 1
            } else if p.goalkeeper && p.action == nil { category = "keeper"; frame = 0 }
            let key = (p.side == .left ? "red-" : "blue-") + category
            if let frames = spriteFrames[key], !frames.isEmpty {
                let f = frames[min(frame, frames.count - 1)]
                sprite.model = ModelComponent(mesh: p.facingX < 0 && abs(p.facingY) <= 0.4 ? f.mirror : f.mesh,
                                               materials: [f.material])
            }
            let fall: Double = p.fallenFor > 0.9 ? (1.15 - p.fallenFor) / 0.25 :
                (p.fallenFor > 0.3 ? 1 : p.fallenFor / 0.3)
            let lean = p.action?.kind == .feint ? sin((p.action?.elapsed ?? 0) / 0.42 * .pi) * 0.2 : 0
            sprite.orientation = simd_quatf(angle: Float(fall * 1.35 + lean) * (p.facingX < 0 ? -1 : 1),
                                           axis: SIMD3<Float>(0, 0, 1))
        }
        let bx = blend(engine.previousBall.x, engine.ball.x) - 52.5
        let bz = blend(engine.previousBall.y, engine.ball.y) - 34
        ballEntity.position = SIMD3<Float>(bx, blend(engine.previousBall.z, engine.ball.z), bz)
        if !engine.paused {
            let axis = simd_normalize(SIMD3<Float>(Float(engine.ball.vy), 0.00001, -Float(engine.ball.vx)))
            ballEntity.orientation = simd_quatf(angle: Float(engine.ball.velocity.length * dt / 0.11), axis: axis) * ballEntity.orientation
        }
        ballShadow.position = SIMD3<Float>(bx, 0.04, bz)
        let selected = engine.players[session.role == .guest ? engine.rightSelectedID : engine.selectedID]
        selectedMarker.position = SIMD3<Float>(Float(selected.x - 52.5), 0.06, Float(selected.y - 34))
        selectedDirection.position = SIMD3<Float>(Float(selected.facingX) * 1.0, 0, Float(selected.facingY) * 1.0)
        selectedDirection.orientation = simd_quatf(angle: Float(atan2(selected.facingX, selected.facingY)), axis: SIMD3<Float>(0, 1, 0))
        let desired = SIMD2<Float>(min(39, max(-39, bx * 0.72 + Float(selected.x - 52.5) * 0.28)),
                                  min(20, max(-20, bz * 0.75 + Float(selected.y - 34) * 0.25)))
        if resetCamera { cameraFocus = desired; resetCamera = false }
        else if !engine.paused { cameraFocus += (desired - cameraFocus) * Float(1 - exp(-dt * 3.2)) }
        camera.look(at: SIMD3<Float>(cameraFocus.x, 0, cameraFocus.y),
                    from: SIMD3<Float>(cameraFocus.x, 32, cameraFocus.y + 27), relativeTo: root)
        miniMap.players = engine.players; miniMap.ball = engine.ball
        miniMap.selectedID = selected.id; miniMap.needsDisplay = true
        let state = engine.paused ? "  정지" : (engine.finished ? "  종료" : "  " + engine.restartLabel)
        scoreLabel.stringValue = "빨강  \(engine.leftScore) : \(engine.rightScore)  파랑    " +
            String(format: "%02d:%02d", Int(engine.remaining) / 60, Int(engine.remaining) % 60) + state
        if let power = inputView.chargePower { scoreLabel.stringValue += "  힘 \(Int(power * 100))%" }
    }
}

@MainActor
private final class ElevenInputView: NSView {
    var onCommand: ((ElevenCommand, Double) -> Void)?
    var isDefending: (() -> Bool)?
    var onPause: (() -> Void)?
    private var pressed = Set<UInt16>()
    private var charge: (key: UInt16, command: ElevenCommand, started: Double)?
    override var acceptsFirstResponder: Bool { true }
    func clear() { pressed.removeAll(); charge = nil }
    var chargePower: Double? {
        charge.map { min(1, max(0.05, (ProcessInfo.processInfo.systemUptime - $0.started) / 0.85)) }
    }
    var currentInput: ElevenInput {
        ElevenInput(horizontal: Double((pressed.contains(124) ? 1 : 0) - (pressed.contains(123) ? 1 : 0)),
                    vertical: Double((pressed.contains(125) ? 1 : 0) - (pressed.contains(126) ? 1 : 0)),
                    sprint: pressed.contains(14))
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift), !event.isARepeat {
            let skill: ElevenCommand? = event.keyCode == 6 ? .roulette : event.keyCode == 7 ? .feint : event.keyCode == 8 ? .rainbow : nil
            if let skill { onCommand?(skill, 0.45); return }
        }
        if [123, 124, 125, 126, 14, 6].contains(event.keyCode) { pressed.insert(event.keyCode); return }
        guard !event.isARepeat else { return }
        switch event.keyCode {
        case 12: onCommand?(.switchPlayer, 0.45)
        case 0, 1, 2:
            if isDefending?() == true {
                onCommand?(event.keyCode == 0 ? .tackle : event.keyCode == 1 ? .switchPlayer : .standing, 0.45)
            } else if charge == nil {
                let action: ElevenCommand = event.keyCode == 0 ? .cross : event.keyCode == 1 ? .pass : pressed.contains(6) ? .curve : .shot
                charge = (event.keyCode, action, ProcessInfo.processInfo.systemUptime)
            }
        case 53: clear(); onPause?()
        default: super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) {
        if let charge, charge.key == event.keyCode {
            var command = charge.command
            if command == .shot && pressed.contains(6) { command = .curve }
            let power = chargePower ?? 0.05
            self.charge = nil; onCommand?(command, power)
        }
        pressed.remove(event.keyCode)
    }
}

@MainActor
private final class ElevenMiniMapView: NSView {
    var players: [ElevenPlayer] = []
    var ball = FootballBall()
    var selectedID = 9
    override func draw(_ dirtyRect: NSRect) {
        let field = bounds.insetBy(dx: 9, dy: 8)
        NSColor(calibratedRed: 0.08, green: 0.29, blue: 0.16, alpha: 0.9).setFill(); field.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        NSBezierPath(rect: field).stroke()
        let middle = NSBezierPath(); middle.move(to: CGPoint(x: field.midX, y: field.minY))
        middle.line(to: CGPoint(x: field.midX, y: field.maxY)); middle.stroke()
        for p in players {
            let point = CGPoint(x: field.minX + field.width * p.x / 105, y: field.minY + field.height * (1 - p.y / 68))
            (p.side == .left ? NSColor.systemRed : NSColor.systemCyan).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
            if p.id == selectedID {
                NSColor.systemYellow.setStroke()
                NSBezierPath(ovalIn: NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).stroke()
            }
        }
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: field.minX + field.width * ball.x / 105 - 3,
                                   y: field.minY + field.height * (1 - ball.y / 68) - 3, width: 6, height: 6)).fill()
    }
}
