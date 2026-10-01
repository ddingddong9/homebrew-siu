import Foundation
import Network

enum DoublesSelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        func check(_ value: Bool, _ name: String) { if !value { failures.append("2v2: \(name)") } }
        var game = DoublesEngine(); game.state.occupied = [0,1,2,3]; game.start()
        game.inputs[0] = DoublesInput(x:1,y:0,sprint:true)
        game.inputs[1] = DoublesInput(x:0,y:-1)
        game.inputs[2] = DoublesInput(x:-1,y:0)
        game.inputs[3] = DoublesInput(x:0,y:1)
        game.tick(dt:1.0/60)
        check(game.state.players[0].x > 0.46 && game.state.players[1].y < 0.7 && game.state.players[2].x < 0.7 && game.state.players[3].y > 0.7, "four independent players")
        check(game.carrier == 0, "kickoff capture")
        game.action("backchop",slot:0)
        check(game.carrier == 0 && game.ball.carrier == .left && game.ball.vx == 0 && game.state.players[0].dx == -1, "back chop turns, does not shoot")
        var pass = DoublesEngine(); pass.start(); pass.carrier = 0
        pass.ball = ArenaBall(x:0.5,y:0.5,carrier:.left); pass.kickoffTeam = nil
        pass.action("pass",slot:0)
        check(pass.carrier == nil && pass.ball.vx < 0 && pass.ball.vy > 0, "S aims at teammate")
        var through = DoublesEngine(); through.start(); through.carrier = 0; through.kickoffTeam = nil
        through.ball = ArenaBall(x:0.5,y:0.5,carrier:.left); through.inputs[1] = DoublesInput(x:1,y:0,sprint:true)
        through.action("through",slot:0)
        check(through.carrier == nil && through.ball.vx > pass.ball.vx && through.ball.vy > 0, "W leads teammate into space")
        let before = game.state.players[1].x; game.action("pause",slot:0); game.tick(dt:0.05)
        check(game.state.players[1].x == before, "pause freezes players")
        var goal = DoublesEngine(); goal.start(); goal.kickoffTeam = nil; goal.ball = ArenaBall(x:0.955,y:0.5,vx:1)
        goal.tick(dt:0.02)
        check(goal.state.red == 1 && goal.kickoffTeam == 1 && goal.state.players[0].move == "celebration", "team goal and conceding kickoff")
        check(!DoublesInput(x:.nan,y:0).valid, "NaN input rejected")
        var invalid = DoublesState(); invalid.players.removeLast(); check(!invalid.valid,"invalid roster rejected")
        if let bytes = DoublesFraming.encode(DoublesPacket(kind:"state",state:goal.state)) {
            var framing = DoublesFraming()
            do {
                let first = try framing.append(Data(bytes.prefix(3)))
                let rest = try framing.append(Data(bytes.dropFirst(3)) + bytes)
                check(first.isEmpty && rest.count == 2 && rest[0].state?.valid == true,"fragmented/coalesced TCP frames")
            } catch { failures.append("2v2 framing decode") }
        } else { failures.append("2v2 framing encode") }
        do { var f = DoublesFraming(); _ = try f.append(Data([0xff,0xff,0xff,0xff])); failures.append("2v2 oversized frame accepted") } catch { }
        return failures
    }

    @MainActor static func runNetwork() -> [String] {
        let host = DoublesSession(), guests = [DoublesSession(),DoublesSession(),DoublesSession()]
        host.approve = { _ in true }
        defer { host.stop(); guests.forEach { $0.stop() } }
        func wait(_ seconds: Double, until condition: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while !condition(), Date() < end { RunLoop.main.run(mode:.default,before:Date().addingTimeInterval(0.02)) }
            return condition()
        }
        do { try host.create() } catch { return ["2v2 TCP host setup: \(error)"] }
        guard wait(3,until:{ host.listeningPort != nil }), let port = host.listeningPort,
              let p = NWEndpoint.Port(rawValue:port) else { return ["2v2 listener readiness"] }
        let room = LocalRoom(name:"test",endpoint:.hostPort(host:"127.0.0.1",port:p))
        for (index, guest) in guests.enumerated() {
            guest.join(room)
            guard wait(3,until:{ guest.slot == index+1 }) else { return ["2v2 slot \(index+1) assignment"] }
        }
        guard wait(3,until:{ host.state.occupied.count == 4 && guests.allSatisfy { $0.state.occupied.count == 4 } }) else { return ["2v2 four-client lobby"] }
        host.startMatch()
        guard wait(3,until:{ guests.allSatisfy { $0.state.running } }) else { return ["2v2 start broadcast"] }
        guests[0].input = DoublesInput(x:1,y:0)
        guard wait(2,until:{ host.state.players[1].x > 0.36 && guests[2].state.players[1].x > 0.35 }) else { return ["2v2 guest input and host snapshot relay"] }
        host.action("pause")
        guard wait(2,until:{ guests.allSatisfy { $0.state.paused } }) else { return ["2v2 pause synchronization"] }
        guests[2].stop()
        guard wait(2,until:{ !host.state.running && host.state.occupied.count == 3 }) else { return ["2v2 disconnect stops game"] }
        return []
    }
}
