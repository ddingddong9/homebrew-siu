import Foundation
import Network
import CryptoKit

enum MatchEventKind: String, Codable, Hashable {
    case ping, pong, ack, start, stop, ball, goal, player, tackle, sync
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
    static let protocolVersion = 4
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
    let actorID: UUID?
    let scores: [String: Int]?
    let remaining: TimeInterval?

    init(kind: MatchEventKind, matchID: UUID? = nil, id: UUID = UUID(),
         duration: TimeInterval? = nil, x: Double? = nil, y: Double? = nil, vx: Double? = nil, vy: Double? = nil,
         actorID: UUID? = nil, scores: [String: Int]? = nil, remaining: TimeInterval? = nil) {
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
        self.actorID = actorID
        self.scores = scores
        self.remaining = remaining
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
    private let listener: NWListener
    private let port: NWEndpoint.Port
    private let outboundPort: NWEndpoint.Port
    private let roomKey: Data
    var onMessage: ((MatchMessage) -> Void)?

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
                guard let self, let data,
                      let message = MatchEnvelope.open(data, key: self.roomKey),
                      message.version == MatchMessage.protocolVersion,
                      abs(message.sentAt.timeIntervalSinceNow) < 30 else {
                    connection.cancel()
                    return
                }
                if message.kind == .ping {
                    let response = MatchMessage(kind: .pong, id: message.id)
                    let encoded = MatchEnvelope.seal(response, key: self.roomKey)
                    connection.send(content: encoded, completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    guard message.kind != .pong, message.kind != .ack else { connection.cancel(); return }
                    let ack = MatchMessage(kind: .ack, id: message.id)
                    let encoded = MatchEnvelope.seal(ack, key: self.roomKey)
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

    func send(_ message: MatchMessage, to host: String, completion: ((Error?) -> Void)? = nil) {
        guard let data = MatchEnvelope.seal(message, key: roomKey) else {
            completion?(BallNetworkingError.encodingFailed)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: outboundPort, using: .udp)
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
                          let ack = MatchEnvelope.open(response, key: self.roomKey),
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
        let request = MatchMessage(kind: .ping)
        guard let data = MatchEnvelope.seal(request, key: roomKey) else { completion(nil); return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: outboundPort, using: .udp)
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
                              let message = MatchEnvelope.open(response, key: self.roomKey),
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
