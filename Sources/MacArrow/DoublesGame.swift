import AppKit
import Network
import CoreImage

struct DoublesPlayer: Codable {
    var x: Double, y: Double
    var dx: Double = 1, dy: Double = 0
    var move: String? = nil
    var animation: Double = 0
}

struct DoublesState: Codable {
    var players = [DoublesPlayer(x: 0.46, y: 0.5), DoublesPlayer(x: 0.3, y: 0.7),
                   DoublesPlayer(x: 0.7, y: 0.5, dx: -1), DoublesPlayer(x: 0.7, y: 0.7, dx: -1)]
    var x = 0.5, y = 0.5, z = 0.0
    var curving = false
    var red = 0, blue = 0
    var remaining = 180.0
    var running = false
    var paused = false
    var occupied = [0]
    var valid: Bool {
        players.count == 4 && players.allSatisfy {
            [$0.x, $0.y, $0.dx, $0.dy, $0.animation].allSatisfy(\.isFinite) &&
            (0.04...0.96).contains($0.x) && (0.08...0.92).contains($0.y) &&
            abs($0.dx) <= 1 && abs($0.dy) <= 1 && (0...3).contains($0.animation)
        } && [x,y,z,remaining].allSatisfy(\.isFinite) && (0...1).contains(x) &&
        (0...1).contains(y) && (0...0.5).contains(z) && (0...180).contains(remaining) &&
        red >= 0 && blue >= 0 && Set(occupied).count == occupied.count && occupied.allSatisfy { (0..<4).contains($0) }
    }
}

struct DoublesInput: Codable {
    var x = 0.0, y = 0.0
    var sprint = false
    var valid: Bool { x.isFinite && y.isFinite && abs(x) <= 1 && abs(y) <= 1 }
}

struct DoublesPacket: Codable {
    var version = 1
    var kind: String
    var slot: Int? = nil
    var input: DoublesInput? = nil
    var state: DoublesState? = nil
    var action: String? = nil
}

struct DoublesFraming {
    private var buffer = Data()
    static let limit = 16_384
    static func encode(_ packet: DoublesPacket) -> Data? {
        guard let data = try? JSONEncoder().encode(packet), data.count <= limit else { return nil }
        var size = UInt32(data.count).bigEndian
        var result = withUnsafeBytes(of: &size) { Data($0) }; result.append(data); return result
    }
    mutating func append(_ data: Data) throws -> [DoublesPacket] {
        buffer.append(data)
        var result: [DoublesPacket] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard (1...Self.limit).contains(size) else { throw CocoaError(.coderReadCorrupt) }
            guard buffer.count >= size + 4 else { break }
            let packet = try JSONDecoder().decode(DoublesPacket.self, from: Data(buffer.dropFirst(4).prefix(size)))
            guard packet.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            result.append(packet); buffer = Data(buffer.dropFirst(size + 4))
        }
        return result
    }
}

struct DoublesEngine {
    var state = DoublesState()
    var inputs = Array(repeating: DoublesInput(), count: 4)
    var ball = ArenaBall.kickoff
    var carrier: Int?
    var kickoffTeam: Int? = 0
    var wait = 0.0
    var cooldown = Array(repeating: 0.0, count: 4)
    static func team(_ slot: Int) -> Int { slot < 2 ? 0 : 1 }
    mutating func start() {
        let occupied = state.occupied
        self = DoublesEngine(); state.occupied = occupied; state.running = true
    }
    mutating func action(_ action: String, slot: Int) {
        guard (0..<4).contains(slot), state.running else { return }
        if action == "pause", slot == 0 { state.paused.toggle(); return }
        guard !state.paused, wait <= 0, cooldown[slot] <= 0,
              kickoffTeam == nil || kickoffTeam == Self.team(slot) else { return }
        let p = state.players[slot], position = CGPoint(x: p.x, y: p.y), direction = CGPoint(x: p.dx, y: p.dy)
        guard carrier == nil || carrier == slot || action == "tackle" else { return }
        switch action {
        case "backchop":
            guard carrier == slot, ArenaPhysics.backheel(&ball, from: position, direction: direction) else { return }
            state.players[slot].dx *= -1; state.players[slot].dy *= -1
            state.players[slot].move = "backheel"; state.players[slot].animation = 0.65
        case "stepover":
            guard carrier == slot else { return }
            state.players[slot].move = "stepover"; state.players[slot].animation = 1
        case "tackle":
            guard ArenaPhysics.tackle(&ball, from: position, direction: direction) else { return }
            carrier = nil
        case "shot", "pass", "through", "curve", "rainbow":
            let success: Bool
            if action == "curve" { success = ArenaPhysics.curveKick(&ball, from: position, direction: direction, toward: slot < 2 ? .right : .left) }
            else if action == "rainbow" { success = carrier == slot && ArenaPhysics.rainbow(&ball, from: position, direction: direction) }
            else if action == "pass" || action == "through" {
                let teammate = slot ^ 1, target = state.players[teammate]
                let lead = action == "through" ? 0.17 : 0.0
                let movement = inputs[teammate], length = hypot(movement.x, movement.y)
                let leadX = length > 0 ? movement.x / length : (slot < 2 ? 1.0 : -1.0)
                let leadY = length > 0 ? movement.y / length : 0
                let tx = min(0.94, max(0.06, target.x + leadX * lead))
                let ty = min(0.9, max(0.1, target.y + leadY * lead))
                let vector = CGPoint(x: tx - ball.x, y: ty - ball.y)
                let distance = hypot(vector.x, vector.y)
                success = ArenaPhysics.kick(&ball, from: position, direction: vector,
                    power: min(1.2, max(0.3, distance * 1.15 + (action == "through" ? 0.15 : 0.08))))
                if success { ball.recatchDelay = 0.25 }
            }
            else { success = ArenaPhysics.kick(&ball, from: position, direction: direction, power: 1) }
            guard success else { return }; carrier = nil
        default: return
        }
        kickoffTeam = nil; cooldown[slot] = 0.8
    }
    mutating func tick(dt: Double) {
        guard state.running, !state.paused else { return }
        let dt = min(max(dt, 0), 0.05)
        state.remaining = max(0, state.remaining - dt)
        if state.remaining == 0 { state.running = false; return }
        wait = max(0, wait - dt)
        for slot in 0..<4 {
            cooldown[slot] = max(0, cooldown[slot] - dt)
            state.players[slot].animation = max(0, state.players[slot].animation - dt)
            if state.players[slot].animation == 0 { state.players[slot].move = nil }
            guard wait == 0, state.players[slot].animation == 0 else { continue }
            let input = inputs[slot], length = hypot(input.x, input.y)
            if length > 0 {
                let dx = input.x / max(1, length), dy = input.y / max(1, length)
                // 20% larger playable space than 1v1: slower normalized travel.
                let speed = input.sprint ? 0.4 : 0.275
                state.players[slot].x = min(0.95, max(0.05, state.players[slot].x + dx * speed * dt))
                state.players[slot].y = min(0.92, max(0.08, state.players[slot].y + dy * speed * dt))
                state.players[slot].dx = input.x / length; state.players[slot].dy = input.y / length
            }
        }
        if wait == 0 {
            for slot in 0..<4 {
                let p = state.players[slot], point = CGPoint(x: p.x, y: p.y)
                if carrier == nil, kickoffTeam == nil || kickoffTeam == Self.team(slot),
                   ArenaPhysics.capture(&ball, by: slot < 2 ? .left : .right, player: point) { carrier = slot; kickoffTeam = nil }
            }
            if let slot = carrier {
                let p = state.players[slot]
                ArenaPhysics.carry(&ball, beside: CGPoint(x: p.x, y: p.y), direction: CGPoint(x: p.dx, y: p.dy),
                    stepoverProgress: p.move == "stepover" ? 1 - p.animation : nil)
            }
            let result = ArenaPhysics.step(&ball, dt: dt)
            if carrier == nil {
                for p in state.players { _ = ArenaPhysics.contact(&ball, player: CGPoint(x:p.x,y:p.y), direction: CGPoint(x:p.dx,y:p.dy)) }
            }
            if result != .inPlay {
                let scoringTeam = result == .goalAtRight ? 0 : 1
                if scoringTeam == 0 { state.red += 1 } else { state.blue += 1 }
                ball = .kickoff; carrier = nil; kickoffTeam = 1 - scoringTeam; wait = 2.3
                state.players = DoublesState().players
                if kickoffTeam == 1 { state.players[0].x = 0.3; state.players[2].x = 0.54 }
                for slot in 0..<4 where Self.team(slot) == scoringTeam {
                    state.players[slot].move = "celebration"; state.players[slot].animation = 2.1
                }
            }
        }
        state.x = ball.x; state.y = ball.y; state.z = ball.z
        state.curving = ball.curveGoal != nil
    }
}

@MainActor
final class DoublesSession {
    static let service = "_siu-doubles._tcp"
    var changed: (() -> Void)?
    var approve: ((String) -> Bool)?
    private(set) var host = false
    private(set) var slot = 0
    private(set) var rooms: [LocalRoom] = []
    private(set) var status = "2대2 · Mac 4대에서 각자 한 선수"
    private(set) var state = DoublesState()
    private var engine = DoublesEngine()
    private var listener: NWListener?
    private var listenerReady = false
    private var approving = false
    private var browser: NWBrowser?
    private var peers: [Int: NWConnection] = [:]
    private var readyPeers = Set<Int>()
    private var frames: [Int: DoublesFraming] = [:]
    private var lastSeen: [Int: Double] = [:]
    private var writes: [Int: Int] = [:]
    private var generation = UUID()
    var input = DoublesInput()
    private var timer: Timer?
    private var ticks = 0
    private var previous = ProcessInfo.processInfo.systemUptime
    var listeningPort: UInt16? { listenerReady ? listener?.port?.rawValue : nil }
    func stop() {
        generation = UUID(); timer?.invalidate(); timer = nil
        listener?.cancel(); listener = nil; listenerReady = false; browser?.cancel(); browser = nil
        peers.values.forEach { $0.cancel() }; peers = [:]; readyPeers = []; frames = [:]; lastSeen = [:]; writes = [:]
        host = false; slot = 0; state = DoublesState(); engine = DoublesEngine(); input = DoublesInput()
        status = "방에서 나왔습니다"; changed?()
    }
    func create() throws {
        stop(); host = true
        let l = try NWListener(using: .tcp, on: .any); listener = l
        l.service = NWListener.Service(name: "SIU 2대2 · \(Host.current().localizedName ?? "Mac")", type: Self.service,
                                      txtRecord: NWTXTRecord(["version": "1"]))
        l.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self, !self.state.running, !self.approving,
                      let slot = (1...3).first(where: { self.peers[$0] == nil }) else { connection.cancel(); return }
                self.approving = true
                defer { self.approving = false }
                guard self.approve?("\(connection.endpoint)") == true else { connection.cancel(); return }
                self.attach(connection, slot: slot)
                if ProcessInfo.processInfo.environment["SIU_NETWORK_TRACE"] == "1" { print("doubles accepted \(slot)") }
            }
        }
        l.stateUpdateHandler = { [weak self] s in
            MainActor.assumeIsolated {
                if case .ready = s { self?.listenerReady = true }
                if case .failed(let e) = s { self?.status = "방 생성 실패: \(e.localizedDescription)"; self?.changed?() }
            }
        }
        l.start(queue: .main); status = "빨강 #1 (방장) · 참가자를 기다립니다 1/4"; startTimer(); changed?()
    }
    func browse() {
        stop()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: nil), using: .tcp); browser = b
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rooms = results.compactMap {
                    guard case .service(let name, _, _, _) = $0.endpoint,
                          case .bonjour(let txt) = $0.metadata, txt["version"] == "1" else { return nil }
                    return LocalRoom(name: name, endpoint: $0.endpoint)
                }.sorted { $0.name < $1.name }
                self.status = self.rooms.isEmpty ? "같은 와이파이에서 2대2 방 검색 중…" : "방을 선택하고 참가하세요"
                self.changed?()
            }
        }
        b.stateUpdateHandler = { [weak self] s in MainActor.assumeIsolated {
            if case .failed = s { self?.status = "방 검색 실패 · 로컬 네트워크 권한을 확인하세요"; self?.changed?() }
        } }
        b.start(queue: .main); changed?()
    }
    func join(_ room: LocalRoom) {
        browser?.cancel(); browser = nil; status = "방장 승인 대기 중…"
        slot = -1; attach(NWConnection(to: room.endpoint, using: .tcp), slot: 0); startTimer(); changed?()
    }
    private func attach(_ connection: NWConnection, slot: Int) {
        peers[slot] = connection; frames[slot] = DoublesFraming(); lastSeen[slot] = ProcessInfo.processInfo.systemUptime
        let generation = generation
        connection.stateUpdateHandler = { [weak self] s in MainActor.assumeIsolated {
            if ProcessInfo.processInfo.environment["SIU_NETWORK_TRACE"] == "1" { print("doubles connection \(slot) host=\(self?.host ?? false): \(s)") }
            guard let self, self.generation == generation else { return }
            switch s {
            case .ready:
                self.readyPeers.insert(slot)
                if self.host { self.send(DoublesPacket(kind: "welcome", slot: slot), to: slot) }
                self.receive(connection, slot: slot, generation: generation)
            case .failed: self.lost(slot)
            default: break
            }
        } }
        connection.start(queue: .main)
    }
    private func receive(_ c: NWConnection, slot: Int, generation: UUID) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, doneContext, done, error in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation, self.peers[slot] === c else { return }
                if let data {
                    do {
                        for packet in try self.frames[slot]!.append(data) { self.accept(packet, slot: slot) }
                    } catch { self.lost(slot); return }
                }
                if done || error != nil { self.lost(slot); return }
                self.receive(c, slot: slot, generation: generation)
            }
        }
    }
    private func accept(_ p: DoublesPacket, slot: Int) {
        if ProcessInfo.processInfo.environment["SIU_NETWORK_TRACE"] == "1", p.kind == "welcome" { print("doubles welcome \(p.slot ?? -1)") }
        lastSeen[slot] = ProcessInfo.processInfo.systemUptime
        if host {
            if p.kind == "input", let i = p.input, i.valid { engine.inputs[slot] = i }
            else if p.kind == "action", let a = p.action { engine.action(a, slot: slot) }
        } else if p.kind == "welcome", let s = p.slot, (1...3).contains(s) { self.slot = s }
        else if p.kind == "state", let s = p.state, s.valid { state = s }
    }
    private func send(_ p: DoublesPacket, to slot: Int) {
        guard readyPeers.contains(slot), let c = peers[slot], let data = DoublesFraming.encode(p), (writes[slot] ?? 0) < 4 else { return }
        writes[slot, default: 0] += 1
        let generation = generation
        c.send(content: data, completion: .contentProcessed { [weak self] error in MainActor.assumeIsolated {
            guard let self, self.generation == generation, self.peers[slot] === c else { return }
            self.writes[slot, default: 1] -= 1
            if error != nil { self.lost(slot) }
        } })
    }
    private func lost(_ slot: Int) {
        peers.removeValue(forKey: slot)?.cancel(); frames[slot] = nil; lastSeen[slot] = nil; writes[slot] = nil
        readyPeers.remove(slot)
        if host { engine.inputs[slot] = DoublesInput(); engine.state.paused = true; engine.state.running = false }
        else { state.running = false; state.paused = true }
        status = "참가자 연결 끊김 · 경기 중단. 인원이 다시 모이면 방장이 새 경기를 시작하세요."
        changed?()
    }
    func startMatch() {
        guard host, readyPeers.count == 3, !engine.state.running else { return }
        engine.state.occupied = [0] + readyPeers.sorted(); engine.start()
    }
    func action(_ a: String) {
        if host { engine.action(a, slot: 0) }
        else if slot >= 1 { send(DoublesPacket(kind: "action", action: a), to: 0) }
    }
    private func startTimer() {
        previous = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime, dt = now - previous; previous = now; ticks += 1
        for s in Array(peers.keys) where now - (lastSeen[s] ?? now) > 8 { lost(s) }
        if host {
            engine.inputs[0] = input; engine.state.occupied = [0] + readyPeers.sorted(); engine.tick(dt: dt); state = engine.state
            for s in peers.keys where now - (lastSeen[s] ?? now) > 0.5 { engine.inputs[s] = DoublesInput() }
            if ticks.isMultiple(of: 3) { for s in peers.keys { send(DoublesPacket(kind: "state", state: state), to: s) } }
        } else if ticks.isMultiple(of: 3) { send(DoublesPacket(kind: "input", input: input), to: 0) }
        if !state.paused && (host || !peers.isEmpty) {
            status = "\(slot < 2 ? "빨강" : "파랑") #\(slot + 1)\(host ? " (방장)" : "") · \(state.occupied.count)/4 · \(state.running ? "경기 중" : "대기")"
        }
        changed?()
    }
}

@MainActor
final class DoublesWindowController: NSWindowController, NSWindowDelegate {
    private let session = DoublesSession()
    private let pitch = DoublesPitchView(frame: .zero)
    private let status = NSTextField(labelWithString: "")
    private let rooms = NSPopUpButton(frame: .zero)
    private var start: NSButton!
    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        super.init(window: w); w.title = "SIU — 2대2 · 4인 LAN"; w.delegate = self; w.center()
        let root = NSView(); w.contentView = root
        let toolbar = NSStackView(); toolbar.orientation = .horizontal; toolbar.spacing = 8
        for (title, selector) in [("방 만들기", #selector(create)), ("방 검색", #selector(browse))] {
            toolbar.addArrangedSubview(NSButton(title: title, target: self, action: selector))
        }
        toolbar.addArrangedSubview(rooms); rooms.widthAnchor.constraint(equalToConstant: 230).isActive = true
        toolbar.addArrangedSubview(NSButton(title: "참가", target: self, action: #selector(join)))
        start = NSButton(title: "4인 경기 시작", target: self, action: #selector(begin)); toolbar.addArrangedSubview(start)
        toolbar.addArrangedSubview(NSButton(title: "방 나가기", target: self, action: #selector(leave)))
        let help = NSTextField(labelWithString: "방향키 이동 · E 달리기 · D 슛 · S 패스 · W 스루패스 · A 태클 · Shift+Q 백숏 · Shift+E 발재간 · Shift+X 사포 · Z+D 커브슛 · Esc 방장 일시정지")
        help.font = .systemFont(ofSize: 12)
        for v in [toolbar, status, pitch, help] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8), status.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            pitch.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8), pitch.leadingAnchor.constraint(equalTo: root.leadingAnchor), pitch.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pitch.bottomAnchor.constraint(equalTo: help.topAnchor, constant: -8), help.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), help.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        pitch.session = session
        session.approve = { endpoint in
            let a = NSAlert(); a.messageText = "2대2 참가 허용"; a.informativeText = "\(endpoint)\n같은 와이파이의 친구가 맞나요? 승인 순서대로 빨강 #2, 파랑 #3, 파랑 #4에 배정됩니다."
            a.addButton(withTitle: "허용"); a.addButton(withTitle: "거절"); return a.runModal() == .alertFirstButtonReturn
        }
        session.changed = { [weak self] in self?.refresh() }; refresh()
    }
    required init?(coder: NSCoder) { nil }
    func show() { showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(pitch) }
    private func refresh() {
        status.stringValue = session.status; start.isEnabled = session.host && session.state.occupied.count == 4 && !session.state.running
        let titles = session.rooms.map(\.name)
        if rooms.itemTitles != titles { rooms.removeAllItems(); rooms.addItems(withTitles: titles) }
        pitch.needsDisplay = true
    }
    @objc private func create() { do { try session.create() } catch { status.stringValue = error.localizedDescription }; window?.makeFirstResponder(pitch) }
    @objc private func browse() { session.browse() }
    @objc private func join() { guard session.rooms.indices.contains(rooms.indexOfSelectedItem) else { return }; session.join(session.rooms[rooms.indexOfSelectedItem]); window?.makeFirstResponder(pitch) }
    @objc private func begin() { session.startMatch(); window?.makeFirstResponder(pitch) }
    @objc private func leave() { session.stop() }
    func windowWillClose(_ notification: Notification) { session.stop() }
    func windowDidResignKey(_ notification: Notification) { pitch.releaseKeys() }
}

@MainActor
final class DoublesPitchView: NSView {
    weak var session: DoublesSession?
    private var keys = Set<UInt16>()
    private let moves = Dictionary(uniqueKeysWithValues: SpecialMove.allCases.map { ($0.rawValue, SpecialMoveAnimation($0)) })
    private var spin = 0.0
    private var lastBall: CGPoint?
    private var trail: [CGPoint] = []
    private var previousPlayers: [DoublesPlayer] = []
    private var movingUntil = Array(repeating: 0.0,count:4)
    private let sprites: [NSImage] = (1...4).compactMap {
        ResourceBundle.images.url(forResource:String(format:"move-%02d",$0),withExtension:"png").flatMap(NSImage.init(contentsOf:))
    }
    private let context = CIContext()
    private var blueImages: [ObjectIdentifier:NSImage] = [:]
    private static let blueCube: Data = {
        var table: [Float] = []
        for b in 0..<16 { for g in 0..<16 { for r in 0..<16 {
            let red = Float(r)/15, green = Float(g)/15, blue = Float(b)/15
            let jersey = red > 0.25 && green < 0.45 && red > green * 1.35 && red > blue * 1.35
            table += [jersey ? blue : red, green, jersey ? red : blue, 1]
        } } }
        return table.withUnsafeBytes { Data($0) }
    }()
    private func teamImage(_ image: NSImage, blue: Bool) -> NSImage {
        guard blue else { return image }
        let key = ObjectIdentifier(image)
        if let cached = blueImages[key] { return cached }
        guard let data = image.tiffRepresentation, let source = CIImage(data:data),
              let filter = CIFilter(name:"CIColorCube") else { return image }
        filter.setValue(16,forKey:"inputCubeDimension"); filter.setValue(Self.blueCube,forKey:"inputCubeData"); filter.setValue(source,forKey:kCIInputImageKey)
        guard let tinted = filter.outputImage else { return image }
        // Limit kit recoloring to the torso: keep face, arms/legs and boots intact.
        let area = source.extent
        let band = CGRect(x:area.minX,y:area.minY+area.height*0.4,width:area.width,height:area.height*0.4)
        let mask = CIImage(color:CIColor.white).cropped(to:band).composited(over:CIImage(color:CIColor.black).cropped(to:area))
        let output = tinted.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:source,kCIInputMaskImageKey:mask])
        guard let cg = context.createCGImage(output,from:area) else { return image }
        let result = NSImage(cgImage:cg,size:image.size); blueImages[key] = result; return result
    }
    override var acceptsFirstResponder: Bool { true }
    func releaseKeys() { keys.removeAll(); session?.input = DoublesInput() }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }; keys.insert(event.keyCode); updateInput(event)
        let shifted = event.modifierFlags.contains(.shift)
        let actions: [UInt16:String] = shifted ? [12:"backchop",14:"stepover",7:"rainbow"] : [2:keys.contains(6) ? "curve" : "shot",1:"pass",13:"through",0:"tackle",53:"pause"]
        if let a = actions[event.keyCode] { session?.action(a) }
    }
    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode); updateInput(event) }
    override func flagsChanged(with event: NSEvent) { updateInput(event) }
    private func updateInput(_ event: NSEvent) {
        session?.input = DoublesInput(x: Double((keys.contains(124) ? 1 : 0) - (keys.contains(123) ? 1 : 0)),
                                     y: Double((keys.contains(126) ? 1 : 0) - (keys.contains(125) ? 1 : 0)), sprint: keys.contains(14) && !event.modifierFlags.contains(.shift))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let session else { return }; let state = session.state
        NSColor(calibratedRed: 0.03, green: 0.18, blue: 0.1, alpha: 1).setFill(); bounds.fill()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * bounds.width, y: y * bounds.height) }
        let field = NSRect(x: bounds.width * 0.04, y: bounds.height * 0.08, width: bounds.width * 0.92, height: bounds.height * 0.84)
        NSColor(calibratedRed: 0.08, green: 0.4, blue: 0.2, alpha: 1).setFill(); field.fill()
        for i in 0..<10 where i.isMultiple(of: 2) { NSColor.white.withAlphaComponent(0.05).setFill(); NSRect(x: field.minX + Double(i) * field.width / 10, y: field.minY, width: field.width / 10, height: field.height).fill() }
        NSColor.white.setStroke(); let lines = NSBezierPath(rect: field); lines.lineWidth = 2
        lines.move(to: pt(0.5,0.08)); lines.line(to: pt(0.5,0.92)); lines.appendOval(in: NSRect(x: bounds.midX-55,y: bounds.midY-55,width:110,height:110))
        for x in [0.04, 0.82] { lines.appendRect(NSRect(x:x*bounds.width,y:bounds.height*0.27,width:bounds.width*0.14,height:bounds.height*0.46)) }; lines.stroke()
        for x in [0.015, 0.96] { NSColor.white.withAlphaComponent(0.35).setFill(); NSRect(x:x*bounds.width,y:bounds.height*0.38,width:bounds.width*0.025,height:bounds.height*0.24).fill() }
        func text(_ string: String, _ p: CGPoint, size: CGFloat = 16, color: NSColor = .white) { (string as NSString).draw(at:p,withAttributes:[.font:NSFont.boldSystemFont(ofSize:size),.foregroundColor:color]) }
        for slot in 0..<4 {
            let p = state.players[slot], center = pt(p.x,p.y), color: NSColor = slot < 2 ? .systemRed : .systemBlue
            let now = ProcessInfo.processInfo.systemUptime
            if previousPlayers.count == 4, hypot(p.x-previousPlayers[slot].x,p.y-previousPlayers[slot].y) > 0.00001 { movingUntil[slot] = now + 0.15 }
            NSColor.black.withAlphaComponent(0.3).setFill(); NSBezierPath(ovalIn:NSRect(x:center.x-22,y:center.y-6,width:44,height:12)).fill()
            let special = p.move.flatMap { moves[$0]?.image(at: ($0 == "celebration" ? 2.1 : $0 == "stepover" ? 1 : 0.65) - p.animation) }
            let walking = sprites.isEmpty ? nil : sprites[now < movingUntil[slot] ? Int(now*9)%sprites.count : 0]
            if let image = special ?? walking, let cg = NSGraphicsContext.current?.cgContext {
                let image = teamImage(image,blue:slot >= 2), height:CGFloat = special == nil ? 110 : 140
                let width = height * image.size.width / max(image.size.height,1)
                cg.saveGState(); cg.translateBy(x:center.x,y:center.y-8)
                if p.dx < -0.1 { cg.scaleBy(x:-1,y:1) }
                image.draw(in:NSRect(x:-width/2,y:0,width:width,height:height)); cg.restoreGState()
            }
            text("\(slot == session.slot ? "▼ 나 · " : "")\(slot < 2 ? "RED" : "BLUE") #\(slot+1)",CGPoint(x:center.x-40,y:center.y-24),size:12,color:color)
            if !state.occupied.contains(slot) { text("접속 대기",CGPoint(x:center.x-30,y:center.y+76),size:12) }
        }
        previousPlayers = state.players
        let b = pt(state.x,state.y), ground = b
        if let lastBall {
            let distance = hypot(b.x-lastBall.x,b.y-lastBall.y)
            if distance > bounds.width * 0.15 { trail.removeAll() }
            else if distance > 0.1 { spin += distance/11; trail.append(lastBall); if trail.count > 12 { trail.removeFirst() } }
            else if !state.curving { trail.removeAll() }
        }; lastBall = b
        if state.curving {
            for (i,p) in trail.enumerated() {
                NSColor.systemYellow.withAlphaComponent(CGFloat(i+1)/CGFloat(max(1,trail.count))*0.45).setFill()
                NSBezierPath(ovalIn:NSRect(x:p.x-7,y:p.y-7,width:14,height:14)).fill()
            }
        }
        NSColor.black.withAlphaComponent(0.25).setFill(); NSBezierPath(ovalIn:NSRect(x:ground.x-13,y:ground.y-5,width:26,height:10)).fill()
        let lifted = CGPoint(x:b.x,y:b.y+state.z*bounds.height)
        NSColor.white.setFill(); NSBezierPath(ovalIn:NSRect(x:lifted.x-11,y:lifted.y-11,width:22,height:22)).fill()
        NSColor.black.setFill(); for i in 0..<3 { let a = spin+Double(i)*2*Double.pi/3; NSBezierPath(ovalIn:NSRect(x:lifted.x+cos(a)*6-3,y:lifted.y+sin(a)*6-3,width:6,height:6)).fill() }
        text("빨강 \(state.red) : \(state.blue) 파랑   |   \(Int(state.remaining)/60):\(String(format:"%02d",Int(state.remaining)%60))\(state.paused ? "  일시정지" : "")",CGPoint(x:bounds.midX-160,y:bounds.height-28),size:20)
    }
}
