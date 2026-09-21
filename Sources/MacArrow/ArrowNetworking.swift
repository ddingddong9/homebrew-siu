import Foundation
import Network

enum BallNetworkingError: LocalizedError {
    case invalidPort(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPort(let value): return "Invalid port: \(value)"
        case .encodingFailed: return "Could not encode the football message."
        }
    }
}

final class BallSender {
    static func send(to host: String, port: UInt16, normalizedY: Double, entryEdge: String = "right", completion: @escaping (Error?) -> Void) {
        let message = BallMessage(normalizedY: normalizedY, entryEdge: entryEdge)
        guard let data = try? JSONEncoder().encode(message),
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(BallNetworkingError.encodingFailed)
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed { error in
                    completion(error)
                    connection.cancel()
                })
            case .failed(let error):
                completion(error)
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }
}

final class BallReceiver {
    private let listener: NWListener
    private let onBall: (BallMessage) -> Void
    private let decoder = JSONDecoder()

    init(port: UInt16, onBall: @escaping (BallMessage) -> Void) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw BallNetworkingError.invalidPort(String(port))
        }
        self.listener = try NWListener(using: .udp, on: nwPort)
        self.onBall = onBall
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            self?.receive(on: connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("Receiver failed: \(error)\n", stderr)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data,
                  let message = try? self.decoder.decode(BallMessage.self, from: data),
                  message.version == BallMessage.protocolVersion,
                  abs(message.sentAt.timeIntervalSinceNow) < 30 else { return }
            self.onBall(message)
        }
    }
}
