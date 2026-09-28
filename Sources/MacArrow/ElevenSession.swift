import Foundation
import Network

enum ElevenCommand: String, Codable { case pass, shot, curve, cross, tackle, standing, feint, roulette, rainbow, switchPlayer, pause, resume }
struct ElevenPacket: Codable {
    static let version = 2
    var version = Self.version
    var kind: String
    var sequence = 0
    var input: ElevenInput?
    var command: ElevenCommand?
    var snapshot: ElevenSnapshot?
    var power: Double?
}

/// TCP is a first LAN transport, not lockstep physics. Length framing must cope
/// with fragmented/coalesced reads and reject oversized messages before decoding.
struct ElevenFraming {
    static let limit = 64 * 1024
    private var buffer = Data()
    static func encode(_ packet: ElevenPacket) -> Data? {
        guard let data = try? JSONEncoder().encode(packet), data.count <= limit else { return nil }
        var length = UInt32(data.count).bigEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(data)
        return result
    }
    mutating func append(_ data: Data) throws -> [ElevenPacket] {
        buffer.append(data)
        var packets: [ElevenPacket] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= Self.limit else { throw CocoaError(.coderReadCorrupt) }
            guard buffer.count >= 4 + size else { break }
            let packet = try JSONDecoder().decode(ElevenPacket.self, from: Data(buffer.dropFirst(4).prefix(size)))
            guard packet.version == ElevenPacket.version else { throw CocoaError(.coderReadCorrupt) }
            packets.append(packet)
            buffer = Data(buffer.dropFirst(4 + size))
        }
        guard buffer.count <= Self.limit + 4 else { throw CocoaError(.coderReadCorrupt) }
        return packets
    }
}

@MainActor
final class ElevenSession {
    static let service = "_siu-eleven._tcp"
    enum Role { case solo, host, guest }
    private(set) var role: Role = .solo
    private(set) var connected = false
    private(set) var remoteInput = ElevenInput()
    private(set) var rooms: [LocalRoom] = []
    private(set) var status = "로컬 연습"
    var onStatus: (() -> Void)?
    var onSnapshot: ((ElevenSnapshot) -> Void)?
    var onCommand: ((ElevenCommand, Double) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var approve: ((String) -> Bool)?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var framing = ElevenFraming()
    private var sequence = 0, receivedSequence = -1
    private var lastReceived = 0.0
    private var pendingWrites = 0
    private var generation = UUID()
    private var listenerReady = false
    var listeningPort: UInt16? {
        guard listenerReady, let port = listener?.port?.rawValue, port != 0 else { return nil }
        return port
    }

    func host(name: String) throws {
        stop()
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        role = .host
        listener.service = NWListener.Service(name: String(name.prefix(40)), type: Self.service,
            txtRecord: NWTXTRecord(["version": String(ElevenPacket.version)]))
        listener.newConnectionHandler = { [weak self] candidate in
            MainActor.assumeIsolated {
                guard let self, self.connection == nil else { candidate.cancel(); return }
                guard self.approve?("\(candidate.endpoint)") == true else { candidate.cancel(); return }
                self.attach(candidate)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .ready = state { self?.listenerReady = true }
                if ProcessInfo.processInfo.environment["SIU_NETWORK_TRACE"] == "1" { print("eleven listener: \(state)") }
                if case .failed(let error) = state { self?.setStatus("방 생성 실패: \(error.localizedDescription)") }
            }
        }
        listener.start(queue: .main)
        setStatus("방 열림 · 친구를 기다리는 중")
    }
    func browse() {
        stop()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rooms = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint,
                          case .bonjour(let txt) = result.metadata,
                          txt["version"] == String(ElevenPacket.version) else { return nil }
                    return LocalRoom(name: name, endpoint: result.endpoint)
                }.sorted { $0.name < $1.name }
                self.setStatus(self.rooms.isEmpty ? "방 검색 중 · 같은 와이파이와 네트워크 권한 확인" : "방 선택 후 참가")
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed = state { self?.setStatus("방 검색 실패 · 로컬 네트워크 권한 확인") }
            }
        }
        browser.start(queue: .main)
        setStatus("같은 와이파이의 방 검색 중")
    }
    func join(_ room: LocalRoom) {
        browser?.cancel(); browser = nil
        role = .guest
        setStatus("연결 중 · 방장의 승인을 기다립니다")
        attach(NWConnection(to: room.endpoint, using: .tcp))
    }
    private func attach(_ candidate: NWConnection) {
        generation = UUID()
        let identity = generation
        connection = candidate; framing = ElevenFraming()
        sequence = 0; receivedSequence = -1; lastReceived = ProcessInfo.processInfo.systemUptime
        candidate.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if ProcessInfo.processInfo.environment["SIU_NETWORK_TRACE"] == "1" { print("eleven peer: \(state)") }
                guard let self, self.generation == identity else { return }
                switch state {
                case .ready:
                    self.send(ElevenPacket(kind: "hello"))
                    self.receive(candidate, identity: identity)
                case .failed: self.lost("연결 실패 · 네트워크 권한/방화벽 확인")
                default: break
                }
            }
        }
        candidate.start(queue: .main)
    }
    private func receive(_ peer: NWConnection, identity: UUID) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, self.generation == identity else { return }
                if let data {
                    do {
                        for packet in try self.framing.append(data) { self.accept(packet) }
                    } catch { self.lost("호환되지 않는 데이터 · 연결 종료"); return }
                }
                if done || error != nil { self.lost("상대 연결이 끊겼습니다 · 경기 일시정지"); return }
                self.receive(peer, identity: identity)
            }
        }
    }
    private func accept(_ packet: ElevenPacket) {
        guard packet.sequence > receivedSequence else { return }
        receivedSequence = packet.sequence
        lastReceived = ProcessInfo.processInfo.systemUptime
        if packet.kind == "hello" && !connected {
            connected = true
            setStatus(role == .host ? "친구 연결됨 · 빨강 팀 · 경기 시작 가능" : "연결됨 · 파랑 팀 · 방장의 시작을 기다립니다")
            onConnected?()
        } else if connected && role == .host && packet.kind == "input", let input = packet.input {
            guard input.horizontal.isFinite, input.vertical.isFinite,
                  abs(input.horizontal) <= 1, abs(input.vertical) <= 1 else { return }
            remoteInput = input
        } else if connected && role == .host && packet.kind == "command", let command = packet.command {
            let power = packet.power ?? 0.45
            guard power.isFinite, (0...1).contains(power) else { return }
            onCommand?(command, power)
        } else if connected && role == .guest && packet.kind == "snapshot", let state = packet.snapshot, state.valid {
            onSnapshot?(state)
        }
    }
    func sendInput(_ input: ElevenInput) { if connected { send(ElevenPacket(kind: "input", input: input)) } }
    func sendCommand(_ command: ElevenCommand, power: Double = 0.45) {
        if connected { send(ElevenPacket(kind: "command", command: command, power: power)) }
    }
    func sendSnapshot(_ snapshot: ElevenSnapshot) {
        if connected { send(ElevenPacket(kind: "snapshot", snapshot: snapshot)) }
    }
    private func send(_ value: ElevenPacket) {
        guard let connection else { return }
        // Snapshots and held input are replaceable; don't build an unbounded backlog.
        if pendingWrites > 2 && (value.kind == "snapshot" || value.kind == "input") { return }
        var packet = value; sequence += 1; packet.sequence = sequence
        guard let data = ElevenFraming.encode(packet) else { return }
        pendingWrites += 1
        let identity = generation
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.generation == identity else { return }
                self.pendingWrites = max(0, self.pendingWrites - 1)
                if error != nil { self.lost("전송 실패 · 경기 일시정지") }
            }
        })
    }
    func checkTimeout(now: Double) {
        guard connection != nil else { return }
        if now - lastReceived > (connected ? 3 : 15) { lost("상대 응답 없음 · 경기 일시정지") }
        else if now - lastReceived > 0.3 { remoteInput = ElevenInput() }
    }
    private func lost(_ message: String) {
        generation = UUID(); connection?.cancel(); connection = nil
        connected = false; remoteInput = ElevenInput(); pendingWrites = 0
        onDisconnect?(); setStatus(message)
    }
    func stop() {
        generation = UUID()
        connection?.cancel(); listener?.cancel(); browser?.cancel()
        connection = nil; listener = nil; browser = nil
        listenerReady = false
        connected = false; role = .solo; rooms = []; remoteInput = ElevenInput()
        pendingWrites = 0; setStatus("로컬 연습")
    }
    private func setStatus(_ text: String) { status = text; onStatus?() }
}
