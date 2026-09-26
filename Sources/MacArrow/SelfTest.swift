import Foundation

enum SelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if !condition { failures.append(name) }
        }

        var kicked = MatchBall.kickoff
        MatchPhysics.kick(&kicked, dx: -1, dy: 0)
        check(kicked.vx < 0 && kicked.vy > 0, "kick direction")

        var transfer = MatchBall(x: 0.025, y: 0.2, vx: -1.5, vy: 0)
        if case .transferred(_, let vx, _) = MatchPhysics.step(&transfer, dt: 1.0 / 60, ownGoal: .right) {
            check(vx < 0, "transfer velocity")
        } else { failures.append("shared-edge transfer") }

        var goal = MatchBall(x: 0.975, y: 0.25, vx: 1.5, vy: 0)
        if case .ownGoal = MatchPhysics.step(&goal, dt: 1.0 / 60, ownGoal: .right) {} else {
            failures.append("own-goal detection")
        }

        var miss = MatchBall(x: 0.975, y: 0.7, vx: 1.5, vy: 0)
        if case .inPlay = MatchPhysics.step(&miss, dt: 1.0 / 60, ownGoal: .right) {
            check(miss.vx < 0, "goal-frame rebound")
        } else { failures.append("high shot should miss goal") }

        var floor = MatchBall(x: 0.5, y: 0.101, vx: 0.4, vy: -1)
        _ = MatchPhysics.step(&floor, dt: 1.0 / 60, ownGoal: .right)
        check(abs(floor.y - 0.10) < 0.001 && floor.vy > 0 && floor.vy < 1, "floor bounce")

        let packet = MatchMessage(kind: .ball, matchID: UUID(), y: 0.4, vx: 1, vy: 0.2)
        if let encoded = try? JSONEncoder().encode(packet),
           let decoded = try? JSONDecoder().decode(MatchMessage.self, from: encoded) {
            check(decoded.kind == .ball && decoded.y == 0.4 && decoded.matchID == packet.matchID, "match packet")
        } else { failures.append("match packet encoding") }

        let sync = MatchMessage(kind: .sync, matchID: UUID(),
                                scores: [GameIdentity.localID.uuidString: 2], remaining: 41)
        if let encoded = try? JSONEncoder().encode(sync),
           let decoded = try? JSONDecoder().decode(MatchMessage.self, from: encoded) {
            check(decoded.scores?[GameIdentity.localID.uuidString] == 2 && decoded.remaining == 41,
                  "score synchronization packet")
        } else { failures.append("score synchronization encoding") }

        let roomKey = Data(repeating: 0xA5, count: 16)
        if let sealed = MatchEnvelope.seal(packet, key: roomKey) {
            check(MatchEnvelope.open(sealed, key: roomKey)?.id == packet.id, "authenticated packet")
            check(MatchEnvelope.open(sealed, key: Data(repeating: 0x5A, count: 16)) == nil,
                  "wrong room code rejected")
            if var forged = try? JSONDecoder().decode(MatchEnvelope.self, from: sealed) {
                let changed = MatchMessage(kind: .goal, matchID: packet.matchID,
                                           id: packet.id, actorID: GameIdentity.localID)
                forged = MatchEnvelope(message: changed, authenticationCode: forged.authenticationCode)
                let tampered = try? JSONEncoder().encode(forged)
                check(tampered.flatMap { MatchEnvelope.open($0, key: roomKey) } == nil,
                      "forged score rejected")
            } else { failures.append("authenticated packet decoding") }
        } else { failures.append("authenticated packet encoding") }

        check(RoomSecretStore.parse("00112233445566778899AABBCCDDEEFF")?.count == 16,
              "pairing code parser")
        check(RoomSecretStore.parse("invalid") == nil, "invalid pairing code")

        var arenaBall = ArenaBall.kickoff
        check(ArenaPhysics.kick(&arenaBall, from: CGPoint(x: 0.46, y: 0.5),
                                direction: CGPoint(x: 1, y: 0)), "arena near-ball kick")
        check(arenaBall.vx > 0 && abs(arenaBall.vy) < 0.001, "arena 360-degree direction")
        check(!ArenaPhysics.kick(&arenaBall, from: CGPoint(x: 0.1, y: 0.1),
                                 direction: CGPoint(x: 1, y: 0)), "arena kick range")
        var leftGoal = ArenaBall(x: 0.041, y: 0.5, vx: -1, vy: 0)
        check(ArenaPhysics.step(&leftGoal, dt: 1.0 / 60) == .goalAtLeft, "arena left goal")
        var rightGoal = ArenaBall(x: 0.959, y: 0.5, vx: 1, vy: 0)
        check(ArenaPhysics.step(&rightGoal, dt: 1.0 / 60) == .goalAtRight, "arena right goal")
        var wall = ArenaBall(x: 0.5, y: 0.081, vx: 0, vy: -1)
        check(ArenaPhysics.step(&wall, dt: 1.0 / 60) == .inPlay && wall.vy > 0,
              "arena sideline rebound")
        var touched = ArenaBall(x: 0.5, y: 0.5)
        ArenaPhysics.contact(&touched, player: CGPoint(x: 0.5, y: 0.5),
                             direction: CGPoint(x: 1, y: 0))
        check(touched.x > 0.53 && touched.vx > 0, "arena player-ball contact")

        let action = MatchMessage(kind: .kick, matchID: UUID(), vx: 0.707, vy: 0.707)
        if let data = try? JSONEncoder().encode(action),
           let decoded = try? JSONDecoder().decode(MatchMessage.self, from: data) {
            check(decoded.kind == .kick && decoded.vx == action.vx, "arena kick packet")
        } else { failures.append("arena kick packet encoding") }

        return failures
    }

    static func runNetwork() -> [String] {
        let port = UInt16.random(in: 52000...62000)
        guard let transport = try? MatchTransport(port: port, roomKey: Data(repeating: 0xA5, count: 16)) else {
            return ["UDP listener setup"]
        }
        let id = UUID()
        var received = false
        var acknowledged = false
        transport.onMessage = { packet in
            received = packet.kind == .start && packet.matchID == id
        }
        transport.start()
        transport.send(MatchMessage(kind: .start, matchID: id, duration: 60), to: "127.0.0.1") { error in
            acknowledged = error == nil
        }
        let deadline = Date().addingTimeInterval(3)
        while (!received || !acknowledged) && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        transport.stop()
        var failures: [String] = []
        if !received { failures.append("UDP packet delivery") }
        if !acknowledged { failures.append("UDP acknowledgement") }
        return failures
    }

    static func runPairSimulation() -> [String] {
        let firstPort = UInt16.random(in: 52000...61998)
        let key = Data(repeating: 0xA5, count: 16)
        guard let a = try? MatchTransport(port: firstPort, remotePort: firstPort + 1, roomKey: key),
              let b = try? MatchTransport(port: firstPort + 1, remotePort: firstPort, roomKey: key) else {
            return ["two-peer UDP setup"]
        }
        let matchID = UUID()
        var seenByA = Set<MatchEventKind>()
        var seenByB = Set<MatchEventKind>()
        var acknowledged = 0
        a.onMessage = { seenByA.insert($0.kind) }
        b.onMessage = { seenByB.insert($0.kind) }
        a.start(); b.start()
        let packets: [(MatchTransport, MatchMessage)] = [
            (a, MatchMessage(kind: .start, matchID: matchID, duration: 60)),
            (a, MatchMessage(kind: .ball, matchID: matchID, x: 0.5, y: 0.3, vx: -1, vy: 0.2)),
            (b, MatchMessage(kind: .player, matchID: matchID, x: 0.7, y: 0.5, vx: -1, vy: 0)),
            (b, MatchMessage(kind: .kick, matchID: matchID, vx: -1, vy: 0)),
            (b, MatchMessage(kind: .stop, matchID: matchID))
        ]
        for (sender, packet) in packets {
            sender.send(packet, to: "127.0.0.1") { error in
                if error == nil { acknowledged += 1 }
            }
        }
        let deadline = Date().addingTimeInterval(4)
        while (seenByA.count < 3 || seenByB.count < 2 || acknowledged < 5) && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        a.stop(); b.stop()
        var failures: [String] = []
        if seenByA != Set([.player, .kick, .stop]) { failures.append("peer A events") }
        if seenByB != Set([.start, .ball]) { failures.append("peer B events") }
        if acknowledged != 5 { failures.append("two-peer acknowledgements") }
        return failures
    }

    static func runWrongRoomSimulation() -> [String] {
        let port = UInt16.random(in: 52000...62000)
        guard let sender = try? MatchTransport(port: port + 1, remotePort: port,
                                               roomKey: Data(repeating: 0xA5, count: 16)),
              let receiver = try? MatchTransport(port: port, remotePort: port + 1,
                                                 roomKey: Data(repeating: 0x5A, count: 16)) else {
            return ["wrong-room UDP setup"]
        }
        var received = false
        var sendFinished = false
        var rejected = false
        receiver.onMessage = { _ in received = true }
        receiver.start()
        sender.send(MatchMessage(kind: .start, matchID: UUID(), duration: 60), to: "127.0.0.1") { error in
            sendFinished = true
            rejected = error != nil
        }
        let deadline = Date().addingTimeInterval(3)
        while !sendFinished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        sender.stop(); receiver.stop()
        return !received && rejected ? [] : ["wrong-room packet rejection"]
    }
}
