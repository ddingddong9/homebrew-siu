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

        return failures
    }

    static func runNetwork() -> [String] {
        let port = UInt16.random(in: 52000...62000)
        guard let transport = try? MatchTransport(port: port) else { return ["UDP listener setup"] }
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
        guard let a = try? MatchTransport(port: firstPort, remotePort: firstPort + 1),
              let b = try? MatchTransport(port: firstPort + 1, remotePort: firstPort) else {
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
            (a, MatchMessage(kind: .ball, matchID: matchID, y: 0.3, vx: -1, vy: 0.2)),
            (b, MatchMessage(kind: .goal, matchID: matchID, actorID: GameIdentity.localID)),
            (b, MatchMessage(kind: .stop, matchID: matchID))
        ]
        for (sender, packet) in packets {
            sender.send(packet, to: "127.0.0.1") { error in
                if error == nil { acknowledged += 1 }
            }
        }
        let deadline = Date().addingTimeInterval(4)
        while (seenByA.count < 2 || seenByB.count < 2 || acknowledged < 4) && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        a.stop(); b.stop()
        var failures: [String] = []
        if seenByA != Set([.goal, .stop]) { failures.append("peer A events") }
        if seenByB != Set([.start, .ball]) { failures.append("peer B events") }
        if acknowledged != 4 { failures.append("two-peer acknowledgements") }
        return failures
    }
}
