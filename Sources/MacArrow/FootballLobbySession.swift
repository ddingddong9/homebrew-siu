import Foundation
import Network
import Darwin

private struct FootballLobbyMessage: Codable {
    let version: Int
    let kind: String
    var address: String? = nil
    var port: UInt16? = nil
}

@MainActor
final class FootballLobbySession {
    static let service = "_siu-football._tcp"
    enum Role { case idle, host, guest }
    private(set) var role: Role = .idle
    private(set) var connected = false
    private(set) var status = "로컬 연습 또는 같은 Wi-Fi의 방을 선택하세요"
    private(set) var rooms: [(name: String, endpoint: NWEndpoint)] = []
    var onChange: (() -> Void)?
    var onStart: ((Bool, String, UInt16) -> Bool)?
    var approve: ((String) -> Bool)?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var guestAddress: String?
    private var receiveBuffer = Data()
    private var generation = UUID()

    func host(name: String) throws {
        stop()
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        role = .host
        listener.service = NWListener.Service(name: String(name.prefix(40)), type: Self.service,
            txtRecord: NWTXTRecord(["version": "1"]))
        listener.newConnectionHandler = { [weak self] candidate in
            MainActor.assumeIsolated {
                guard let self, self.connection == nil else { candidate.cancel(); return }
                guard self.approve?("\(candidate.endpoint)") == true else { candidate.cancel(); return }
                self.attach(candidate)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .ready = state { self?.setStatus("빨강 팀 · 친구 참가 대기 중") }
                if case .failed(let error) = state { self?.setStatus("방 생성 실패: \(error.localizedDescription)") }
            }
        }
        listener.start(queue: .main)
        setStatus("방 준비 중…")
    }

    func browse() {
        stop()
        role = .guest
        let browser = NWBrowser(for: .bonjour(type: Self.service, domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rooms = results.map { result in
                    let name: String
                    if case .service(let serviceName, _, _, _) = result.endpoint { name = serviceName }
                    else { name = "SIU 방" }
                    return (name, result.endpoint)
                }.sorted { $0.name < $1.name }
                self.onChange?()
                self.setStatus(self.rooms.isEmpty ? "같은 Wi-Fi의 SIU 방 검색 중…" : "파랑 팀 · 방을 선택하고 참가하세요")
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed(let error) = state { self?.setStatus("방 검색 실패: \(error.localizedDescription)") }
            }
        }
        browser.start(queue: .main)
        setStatus("같은 Wi-Fi의 SIU 방 검색 중…")
    }

    func join(index: Int) {
        guard rooms.indices.contains(index), connection == nil else { return }
        let peer = NWConnection(to: rooms[index].endpoint, using: .tcp)
        attach(peer)
        setStatus("방장 승인 대기 중…")
    }

    func startMatch(port: UInt16 = 38245) -> Bool {
        guard role == .host, connected, let address = Self.wifiIPv4(), let guestAddress else {
            setStatus("경기 시작 실패 · 친구 연결 또는 Wi-Fi IPv4 주소를 확인하세요")
            return false
        }
        guard onStart?(true, guestAddress, port) == true else {
            setStatus("방장 경기 실행에 실패했습니다")
            return false
        }
        send(FootballLobbyMessage(version: 1, kind: "start", address: address, port: port))
        setStatus("빨강 팀 · 경기 실행 중")
        return true
    }

    private func attach(_ peer: NWConnection) {
        connection = peer
        receiveBuffer.removeAll()
        let identity = generation
        peer.stateUpdateHandler = { [weak self, weak peer] state in
            MainActor.assumeIsolated {
                guard let self, let peer, self.generation == identity else { return }
                switch state {
                case .ready:
                    if self.role == .guest {
                        guard let address = Self.wifiIPv4() else {
                            self.lost("Wi-Fi IPv4 주소를 찾을 수 없습니다")
                            return
                        }
                        self.send(FootballLobbyMessage(version: 1, kind: "hello", address: address))
                    }
                    self.receive(peer, identity: identity)
                case .failed(let error): self.lost("연결 실패: \(error.localizedDescription)")
                case .cancelled: self.lost("연결 종료")
                default: break
                }
            }
        }
        peer.start(queue: .main)
    }

    private func receive(_ peer: NWConnection, identity: UUID) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak peer] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, let peer, self.generation == identity else { return }
                if let data { self.receiveBuffer.append(data) }
                if self.receiveBuffer.count > 8192 { self.lost("잘못된 로비 메시지"); return }
                while let newline = self.receiveBuffer.firstIndex(of: 10) {
                    let line = Data(self.receiveBuffer[..<newline])
                    self.receiveBuffer.removeSubrange(...newline)
                    guard let message = try? JSONDecoder().decode(FootballLobbyMessage.self, from: line),
                          message.version == 1 else { self.lost("호환되지 않는 로비 메시지"); return }
                    self.accept(message)
                }
                if done || error != nil { self.lost("친구 연결이 끊겼습니다"); return }
                self.receive(peer, identity: identity)
            }
        }
    }

    private func accept(_ message: FootballLobbyMessage) {
        if role == .host && message.kind == "hello", let address = message.address,
           Self.validIPv4(address) {
            guestAddress = address
            connected = true
            send(FootballLobbyMessage(version: 1, kind: "welcome"))
            setStatus("빨강 팀 · 친구 연결됨 · 경기 시작 가능")
        } else if role == .guest && message.kind == "welcome" {
            connected = true
            setStatus("파랑 팀 · 연결됨 · 방장의 경기 시작 대기 중")
        } else if role == .guest && connected && message.kind == "start",
                  let address = message.address, let port = message.port,
                  port > 0, Self.validIPv4(address) {
            if onStart?(false, address, port) == true { setStatus("파랑 팀 · 경기 실행 중") }
            else { setStatus("참가자 경기 실행에 실패했습니다") }
        }
    }

    private func send(_ message: FootballLobbyMessage) {
        guard let connection, let data = try? JSONEncoder().encode(message) else { return }
        connection.send(content: data + Data([10]), completion: .contentProcessed { _ in })
    }

    private func lost(_ message: String) {
        generation = UUID()
        connection?.cancel(); connection = nil
        connected = false
        guestAddress = nil
        setStatus(message)
    }

    func stop() {
        generation = UUID()
        connection?.cancel(); listener?.cancel(); browser?.cancel()
        connection = nil; listener = nil; browser = nil
        connected = false; role = .idle; rooms = []
        guestAddress = nil
        setStatus("로컬 연습 또는 같은 Wi-Fi의 방을 선택하세요")
    }

    private func setStatus(_ value: String) { status = value; onChange?() }

    private static func validIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) == 1 }
    }

    private static func wifiIPv4() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let address = item.pointee.ifa_addr
            if String(cString: item.pointee.ifa_name) == "en0", address?.pointee.sa_family == UInt8(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var ipv4 = UnsafeRawPointer(address!).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                _ = inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(buffer.count))
                return String(cString: buffer)
            }
            cursor = item.pointee.ifa_next
        }
        return nil
    }
}
