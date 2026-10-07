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
        var selection = DoublesEngine(); selection.state.occupied = [0,1,2,3]
        selection.selectTeam(1,slot:0)
        check(selection.state.teams == [1,0,0,1] && selection.state.valid,"balanced team swap")
        selection.start(); selection.carrier = 0; selection.kickoffTeam = nil
        check(selection.state.team(0) == 1 && selection.state.players[0].x == 0.7,"selection survives start and spawns on correct side")
        selection.ball = ArenaBall(x:0.7,y:0.5,carrier:.right)
        selection.action("pass",slot:0)
        check(selection.ball.vy > 0,"pass targets selected teammate rather than original slot")
        let teams = selection.state.teams; selection.selectTeam(0,slot:0)
        check(selection.state.teams == teams,"team change blocked in game")
        var unbalanced = DoublesState(); unbalanced.teams = [0,0,0,1]; check(!unbalanced.valid,"3v1 rejected")
        var tackling = DoublesEngine(); tackling.start(); tackling.kickoffTeam = nil
        tackling.state.players[0].x = 0.4; tackling.state.players[2].x = 0.6
        tackling.ball = ArenaBall(x:0.6,y:0.5,carrier:.right); tackling.carrier = 2
        tackling.action("tackle",slot:0)
        check(tackling.motions[0].isSliding,"tackle starts away from ball")
        for _ in 0..<30 { tackling.tick(dt:1.0/60) }
        check(tackling.state.players[0].x > 0.55 && tackling.state.players[2].stunned > 0 && tackling.carrier != 2,"slide hits during travel and releases possession")
        var running = DoublesEngine(); running.start(); running.inputs[1] = DoublesInput(x:1,y:0,sprint:true)
        for _ in 0..<270 { running.tick(dt:1.0/60) }
        check(running.state.players[1].stamina < 20,"2v2 synchronized stamina drains")
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
        guests[2].selectTeam(.ronaldo)
        guard wait(3,until:{ host.state.team(3) == 0 && guests.allSatisfy{$0.state.teams == host.state.teams} }) else { return ["2v2 team selection synchronization"] }
        guests[2].selectTeam(.messi)
        // Rate limiting requires a short run-loop gap before another team exchange.
        _ = wait(0.6,until:{false}); guests[2].selectTeam(.messi)
        guard wait(3,until:{ host.state.teams == [0,0,1,1] && guests.allSatisfy{$0.state.teams == host.state.teams} }) else { return ["2v2 team re-selection synchronization"] }
        host.startMatch()
        guard wait(3,until:{ guests.allSatisfy { $0.state.running } }) else { return ["2v2 start broadcast"] }
        // Simulate a UI run-loop mode that prevents game timers from firing.
        // An idle TCP connection must survive longer than the old 8s limit.
        let blockedMode = RunLoop.Mode("SIUDoublesTimeoutRegression")
        let keepAlive = Timer(timeInterval:0.05,repeats:true) { _ in }
        RunLoop.main.add(keepAlive,forMode:blockedMode)
        let blockedUntil = Date().addingTimeInterval(8.3)
        while Date() < blockedUntil { RunLoop.main.run(mode:blockedMode,before:Date().addingTimeInterval(0.05)) }
        keepAlive.invalidate()
        _ = wait(0.2,until:{false})
        guard host.state.running,host.state.occupied.count == 4,guests.allSatisfy({$0.state.running}) else { return ["2v2 idle period must not disconnect players"] }
        guests[0].input = DoublesInput(x:1,y:0,sprint:true)
        guard wait(2,until:{ host.state.players[1].x > 0.36 && guests[2].state.players[1].x > 0.35 && guests[2].state.players[1].stamina < 97 }) else { return ["2v2 guest input, stamina and host snapshot relay"] }
        host.action("pause")
        guard wait(2,until:{ guests.allSatisfy { $0.state.paused } }) else { return ["2v2 pause synchronization"] }
        guests[2].stop()
        guard wait(2,until:{ !host.state.running && host.state.occupied.count == 3 }) else { return ["2v2 disconnect stops game"] }
        return []
    }
}
