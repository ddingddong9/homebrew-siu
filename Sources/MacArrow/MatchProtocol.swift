import Foundation
import Network
import CryptoKit

enum MatchEventKind: String, Codable, Hashable {
    case ping, pong, ack, start, stop, ball, goal, player, kick, tackle, fall, kickoff, powerShot, marseille, rainbow, phantom, curveShot, pause, resume, sync
}

struct RoomJoinRequest: Codable {
    let version: Int
    let id: UUID
    let playerID: UUID
    let playerName: String

    init(playerName: String, playerID: UUID = GameIdentity.localID) {
        version = MatchMessage.protocolVersion
        id = UUID()
        self.playerID = playerID
        self.playerName = playerName
    }
}

struct RoomJoinResponse: Codable {
    let version: Int
    let requestID: UUID
    let hostID: UUID
    let roomKey: Data?
}

enum GameIdentity {
    static let localID = UUID()
}

enum RoomPairingError: LocalizedError {
    case pairingRequired

    var errorDescription: String? {
        "경기 연결에 페어링 코드가 필요합니다. 한 Mac에서 `siu pair-code`, 다른 Mac에서 `siu pair`를 실행하세요."
    }
}

struct MatchMessage: Codable {
    static let protocolVersion = 9
    let version: Int
    let id: UUID
    let senderID: UUID
    let kind: MatchEventKind
    let matchID: UUID?
    let sentAt: Date
    let duration: TimeInterval?
    let y: Double?
    let x: Double?
    let vx: Double?
    let vy: Double?
    let z: Double?
    let vz: Double?
    let curve: Double?
    let actorID: UUID?
    let scores: [String: Int]?
    let remaining: TimeInterval?
    let possession: Double?

    init(kind: MatchEventKind, matchID: UUID? = nil, id: UUID = UUID(),
         duration: TimeInterval? = nil, x: Double? = nil, y: Double? = nil, vx: Double? = nil, vy: Double? = nil,
         z: Double? = nil, vz: Double? = nil, curve: Double? = nil,
         actorID: UUID? = nil, scores: [String: Int]? = nil, remaining: TimeInterval? = nil,
         possession: Double? = nil) {
        version = Self.protocolVersion
        self.id = id
        senderID = GameIdentity.localID
        self.kind = kind
        self.matchID = matchID
        sentAt = Date()
        self.duration = duration
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.z = z
        self.vz = vz
        self.curve = curve
        self.actorID = actorID
        self.scores = scores
        self.remaining = remaining
        self.possession = possession
    }
}

struct MatchEnvelope: Codable {
    let message: MatchMessage
    let authenticationCode: Data

    static func seal(_ message: MatchMessage, key: Data) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(message) else { return nil }
        let mac = Data(HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: key)))
        return try? encoder.encode(MatchEnvelope(message: message, authenticationCode: mac))
    }

    static func open(_ data: Data, key: Data) -> MatchMessage? {
        guard let envelope = try? JSONDecoder().decode(MatchEnvelope.self, from: data) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(envelope.message),
              HMAC<SHA256>.isValidAuthenticationCode(envelope.authenticationCode,
                                                       authenticating: payload,
                                                       using: SymmetricKey(data: key)) else { return nil }
        return envelope.message
    }
}

final class MatchTransport {
    static let roomServiceType = "_siu-match._udp"
    private let listener: NWListener
    private let port: NWEndpoint.Port
    private let outboundPort: NWEndpoint.Port
    private let keyLock = NSLock()
    private var roomKey: Data
    var onMessage: ((MatchMessage) -> Void)?
    var onPeerPing: ((NWEndpoint, UUID) -> Void)?
    var onJoinRequest: ((RoomJoinRequest, @escaping (Bool) -> Void) -> Void)?

    var currentKey: Data {
        keyLock.lock()
        defer { keyLock.unlock() }
        return roomKey
    }

    func useRoomKey(_ key: Data) {
        precondition(key.count == 16)
        keyLock.lock()
        roomKey = key
        keyLock.unlock()
    }

    func advertiseRoom(named name: String?) {
        listener.service = name.map {
            NWListener.Service(name: "\($0) · \(GameIdentity.localID.uuidString.prefix(4))",
                               type: Self.roomServiceType,
                               txtRecord: NWTXTRecord(["version": String(MatchMessage.protocolVersion)]))
        }
    }

    init(port: UInt16, remotePort: UInt16? = nil, roomKey: Data? = nil) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let peerPort = NWEndpoint.Port(rawValue: remotePort ?? port) else {
            throw BallNetworkingError.invalidPort(String(port))
        }
        self.port = nwPort
        outboundPort = peerPort
        guard let roomKey = roomKey ?? RoomSecretStore.load(), roomKey.count == 16 else {
            throw RoomPairingError.pairingRequired
        }
        self.roomKey = roomKey
        listener = try NWListener(using: .udp, on: nwPort)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            connection.receiveMessage { [weak self] data, _, _, _ in
                guard let self, let data else { connection.cancel(); return }
                if let request = try? JSONDecoder().decode(RoomJoinRequest.self, from: data) {
                    guard data.count <= 1024, request.version == MatchMessage.protocolVersion,
                          request.playerID != GameIdentity.localID,
                          (1...40).contains(request.playerName.count) else {
                        connection.cancel()
                        return
                    }
                    DispatchQueue.main.async {
                        guard let approve = self.onJoinRequest else { connection.cancel(); return }
                        approve(request) { accepted in
                            let reply = RoomJoinResponse(version: MatchMessage.protocolVersion,
                                                         requestID: request.id,
                                                         hostID: GameIdentity.localID,
                                                         roomKey: accepted ? self.currentKey : nil)
                            let encoded = try? JSONEncoder().encode(reply)
                            connection.send(content: encoded, completion: .contentProcessed { _ in
                                connection.cancel()
                            })
                        }
                    }
                    return
                }
                let key = self.currentKey
                guard let message = MatchEnvelope.open(data, key: key),
                      message.version == MatchMessage.protocolVersion,
                      abs(message.sentAt.timeIntervalSinceNow) < 30 else {
                    connection.cancel()
                    return
                }
                if message.kind == .ping {
                    let response = MatchMessage(kind: .pong, id: message.id)
                    let encoded = MatchEnvelope.seal(response, key: key)
                    connection.send(content: encoded, completion: .contentProcessed { _ in connection.cancel() })
                    if case .hostPort(let host, _) = connection.endpoint {
                        let peerEndpoint = NWEndpoint.hostPort(host: host, port: self.outboundPort)
                        DispatchQueue.main.async { self.onPeerPing?(peerEndpoint, message.senderID) }
                    }
                } else {
                    guard message.kind != .pong, message.kind != .ack else { connection.cancel(); return }
                    let ack = MatchMessage(kind: .ack, id: message.id)
                    let encoded = MatchEnvelope.seal(ack, key: key)
                    connection.send(content: encoded, completion: .contentProcessed { _ in connection.cancel() })
                    DispatchQueue.main.async { self.onMessage?(message) }
                }
            }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { fputs("Match receiver failed: \(error)\n", stderr) }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() { listener.cancel() }

    func endpoint(for host: String) -> NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: outboundPort)
    }

    func requestJoin(endpoint: NWEndpoint, playerName: String,
                     playerID: UUID = GameIdentity.localID,
                     completion: @escaping (Data?, UUID?) -> Void) {
        let request = RoomJoinRequest(playerName: playerName, playerID: playerID)
        guard let encoded = try? JSONEncoder().encode(request) else {
            completion(nil, nil)
            return
        }
        let connection = NWConnection(to: endpoint, using: .udp)
        let queue = DispatchQueue(label: "siu.room.join.\(request.id.uuidString)")
        let lock = NSLock()
        var finished = false
        func finish(_ key: Data?, _ hostID: UUID?) {
            lock.lock()
            let shouldFinish = !finished
            finished = true
            lock.unlock()
            guard shouldFinish else { return }
            connection.cancel()
            DispatchQueue.main.async { completion(key, hostID) }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: encoded, completion: .contentProcessed { error in
                    if error != nil { finish(nil, nil); return }
                    connection.receiveMessage { response, _, _, _ in
                        guard let response,
                              let reply = try? JSONDecoder().decode(RoomJoinResponse.self, from: response),
                              reply.version == MatchMessage.protocolVersion,
                              reply.requestID == request.id,
                              let key = reply.roomKey, key.count == 16 else {
                            finish(nil, nil)
                            return
                        }
                        finish(key, reply.hostID)
                    }
                })
            case .failed: finish(nil, nil)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 60) { finish(nil, nil) }
    }

    func send(_ message: MatchMessage, to host: String, completion: ((Error?) -> Void)? = nil) {
        send(message, to: endpoint(for: host), completion: completion)
    }

    func send(_ message: MatchMessage, to endpoint: NWEndpoint,
              completion: ((Error?) -> Void)? = nil) {
        let key = currentKey
        guard let data = MatchEnvelope.seal(message, key: key) else {
            completion?(BallNetworkingError.encodingFailed)
            return
        }
        let connection = NWConnection(to: endpoint, using: .udp)
        let queue = DispatchQueue(label: "siu.match.send.\(message.id.uuidString)")
        var attempts = 0
        var finished = false
        func finish(_ error: Error?) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { completion?(error) }
        }
        func attempt() {
            guard !finished else { return }
            guard attempts < 3 else {
                finish(BallNetworkingError.timedOut)
                return
            }
            attempts += 1
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { finish(error) }
            })
            queue.asyncAfter(deadline: .now() + 0.35) { attempt() }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.receiveMessage { response, _, _, _ in
                    guard let response,
                          let ack = MatchEnvelope.open(response, key: key),
                          ack.kind == .ack, ack.id == message.id else {
                        finish(BallNetworkingError.timedOut)
                        return
                    }
                    finish(nil)
                }
                attempt()
            case .failed(let error):
                finish(error)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func ping(host: String, completion: @escaping (UUID?) -> Void) {
        ping(endpoint: endpoint(for: host), completion: completion)
    }

    func ping(endpoint: NWEndpoint, completion: @escaping (UUID?) -> Void) {
        let request = MatchMessage(kind: .ping)
        let key = currentKey
        guard let data = MatchEnvelope.seal(request, key: key) else { completion(nil); return }
        let connection = NWConnection(to: endpoint, using: .udp)
        let lock = NSLock()
        var finished = false
        func finish(_ peerID: UUID?) {
            lock.lock()
            let shouldFinish = !finished
            finished = true
            lock.unlock()
            guard shouldFinish else { return }
            connection.cancel()
            DispatchQueue.main.async { completion(peerID) }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed { error in
                    if error != nil { finish(nil); return }
                    connection.receiveMessage { response, _, _, _ in
                        guard let response,
                              let message = MatchEnvelope.open(response, key: key),
                              message.kind == .pong, message.id == request.id else { finish(nil); return }
                        finish(message.senderID)
                    }
                })
            case .failed: finish(nil)
            default: break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) { finish(nil) }
    }
}
