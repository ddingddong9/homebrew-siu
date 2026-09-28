import Foundation

enum ElevenSelfTests {
    static func run() -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) { if !condition { failures.append("eleven: " + name) } }
        func ready() -> ElevenMatchEngine {
            var e = ElevenMatchEngine(duration: 300, aiEnabled: false)
            e.step(input: ElevenInput(), dt: 1.5)
            return e
        }
        let base = ready()
        check(base.players.count == 22 && base.players.filter { $0.side == .left }.count == 11, "22 players")
        check(base.players.filter(\.goalkeeper).count == 2, "two goalkeepers")
        check(base.carrierID == 9 && base.ball.carrier == .left, "kickoff owner")
        var switcher = base
        switcher.switchPlayer()
        check(switcher.selectedID != 9 && switcher.selected.side == .left, "selection stays in team")
        switcher.switchPlayer(side: .right)
        check(switcher.rightSelectedID != 20 && switcher.rightSelectedID >= 11, "remote team selection")
        var horizontal = base, vertical = base, diagonal = base
        for _ in 0..<60 {
            horizontal.step(input: ElevenInput(horizontal: 1), dt: 1 / 60.0)
            vertical.step(input: ElevenInput(vertical: -1), dt: 1 / 60.0)
            diagonal.step(input: ElevenInput(horizontal: 1, vertical: -1), dt: 1 / 60.0)
        }
        let dx = horizontal.selected.x - base.selected.x
        let dy = base.selected.y - vertical.selected.y
        let dd = (diagonal.selected.position - base.selected.position).length
        check(abs(dx - dy) < 0.00001 && abs(dx - dd) < 0.00001, "metric speed equal all directions")
        check(abs(horizontal.selected.speed - 4.8) < 0.00001 && dx < 4.8, "acceleration and run limit")
        var start = base
        start.step(input: ElevenInput(horizontal: 1, sprint: true), dt: 1 / 60.0)
        check(start.selected.speed > 0 && start.selected.speed < 0.3, "no instant acceleration")
        let oldFacing = horizontal.selected.facingX
        horizontal.step(input: ElevenInput(horizontal: -1), dt: 1 / 60.0)
        check(horizontal.selected.facingX > 0.9 && oldFacing > 0.9, "180 turn is not instantaneous")
        horizontal.step(input: ElevenInput(), dt: 0.4)
        check(horizontal.selected.speed < 0.001, "braking reaches rest")
        var sprint = base
        sprint.step(input: ElevenInput(horizontal: 1, sprint: true), dt: 1)
        check(abs(sprint.selected.speed - 7.2) < 0.001, "sprint limit")
        check((sprint.ball.position - sprint.selected.position).length < 1.7, "short dribble touches")
        check(sprint.ball.velocity.length > 0, "dribble ball rolls")
        var frames: [ElevenMatchEngine] = []
        for fps in [30, 60, 120] {
            var e = base
            for _ in 0..<(fps * 2) { e.step(input: ElevenInput(vertical: -1), dt: 1 / Double(fps)) }
            frames.append(e)
        }
        check(frames.allSatisfy { abs($0.selected.y - frames[0].selected.y) < 1e-8 &&
            $0.simulationTicks == frames[0].simulationTicks }, "30/60/120 identical fixed steps")
        var stall = base, regular = base
        stall.step(input: ElevenInput(horizontal: 1), dt: 0.2)
        for _ in 0..<12 { regular.step(input: ElevenInput(horizontal: 1), dt: 1 / 60.0) }
        check(abs(stall.selected.x - regular.selected.x) < 1e-8, "200ms does not discard time")
        var shot = base
        shot.shoot(); shot.shoot()
        check(shot.contactCount == 0 && shot.carrierID == 9, "shot waits for foot contact")
        shot.step(input: ElevenInput(), dt: 0.15)
        check(shot.contactCount == 0, "shot windup")
        shot.step(input: ElevenInput(), dt: 0.05)
        check(shot.contactCount == 1 && shot.ball.carrier == nil && shot.ball.velocity.length > 20, "single contact shot")
        shot.step(input: ElevenInput(), dt: 0.15)
        check(shot.contactCount == 1, "no repeated shot")
        var pass = base
        pass.pass(); pass.step(input: ElevenInput(), dt: 0.2)
        check(pass.contactCount == 1 && pass.ball.velocity.length >= 8, "delayed pass")
        check(pass.selectedID != 9 && pass.receiverID == pass.selectedID, "pass immediately selects intended receiver")
        let intended = pass.selectedID
        let receiverStart = pass.players[intended].position
        for _ in 0..<240 where pass.carrierID == nil { pass.step(input: ElevenInput(), dt: 1 / 60.0) }
        check(pass.carrierID == intended, "assisted pass reaches teammate")
        check((pass.players[intended].position - receiverStart).length > 0.2, "receiver moves to meet pass")
        var resting = base
        resting.step(input: ElevenInput(), dt: 3)
        check(resting.ball.velocity.length == 0, "idle dribble settles completely")
        var looseState = base.snapshot
        looseState.ball = FootballBall(x: 52, y: 4, vx: 3)
        var loose = ElevenMatchEngine(scenario: looseState)
        loose.step(input: ElevenInput(), dt: 2)
        check(loose.ball.velocity.length == 0 && loose.ball.x < 54, "free ball rolls to stop")
        var weak = base, strong = base, curved = base, cross = base
        weak.shoot(power: 0.05); strong.shoot(power: 1); curved.shoot(curved: true)
        cross.cross(power: 0.7)
        for _ in 0..<15 {
            weak.step(input: ElevenInput(), dt: 1 / 60.0); strong.step(input: ElevenInput(), dt: 1 / 60.0)
            curved.step(input: ElevenInput(), dt: 1 / 60.0); cross.step(input: ElevenInput(), dt: 1 / 60.0)
        }
        check(strong.ball.velocity.length > weak.ball.velocity.length + 15, "hold duration scales shot strength")
        check(weak.ball.velocity.length > 18 && strong.ball.velocity.length > 36, "tap and charged shots have responsive pace")
        check(curved.ball.vx > 0 && abs(curved.ball.curve) > 0.1, "curved shot goes toward opposing goal")
        check(cross.ball.vz > 1 && cross.ball.z > 0.2 && cross.ball.velocity.length > 25, "cross has driven pace and distance-matched loft")
        var passingState = base.snapshot
        passingState.players[9].x = 40; passingState.players[9].y = 34
        passingState.players[8].x = 60; passingState.players[8].y = 34
        passingState.ball = FootballBall(x: 40.6, y: 34, carrier: .left)
        var pacedPass = ElevenMatchEngine(scenario: passingState)
        pacedPass.pass(power: 0.45)
        check(pacedPass.selectedID == 8, "twenty metre pass selects aligned teammate")
        pacedPass.step(input: ElevenInput(), dt: 0.2)
        check(pacedPass.ball.velocity.length > 13, "twenty metre pass has improved launch pace")
        for _ in 0..<120 where pacedPass.carrierID == nil { pacedPass.step(input: ElevenInput(), dt: 1 / 60.0) }
        check(pacedPass.carrierID == 8, "faster pass remains receivable within two seconds")
        var rainbow = base, roulette = base
        rainbow.skill(.rainbow); roulette.skill(.roulette)
        rainbow.step(input: ElevenInput(), dt: 0.25); roulette.step(input: ElevenInput(), dt: 0.3)
        check(rainbow.ball.vz > 4 && rainbow.ball.carrier == nil, "rainbow lifts ball over challenge")
        check(roulette.players[9].facingX < -0.8, "roulette rotates facing through full turn")
        var feint = base
        feint.feint()
        check(feint.selected.y == base.selected.y, "feint no teleport")
        feint.step(input: ElevenInput(), dt: 0.2)
        check(feint.selected.y > base.selected.y && feint.selected.y - base.selected.y < 1, "feint travels over time")
        let elapsed = feint.selected.action?.elapsed
        feint.feint()
        check(feint.selected.action?.elapsed == elapsed, "action cannot be overwritten")
        var paused = feint
        paused.togglePause()
        let frozen = paused.snapshot
        paused.step(input: ElevenInput(horizontal: 1), dt: 3)
        check(paused.remaining == frozen.remaining && paused.selected.x == frozen.players[9].x &&
              paused.selected.action?.elapsed == elapsed, "pause freezes clock action physics")
        var state = base.snapshot
        state.ball = FootballBall(x: 104.9, y: 34, vx: 25)
        var goal = ElevenMatchEngine(scenario: state)
        goal.step(input: ElevenInput(), dt: 0.05)
        check(goal.leftScore == 1 && goal.ball.carrier == .right && goal.carrierID == 20 &&
              goal.kickoffFor > 0, "whole-ball goal and conceding kickoff")
        state.ball = FootballBall(x: 104.9, y: 34, z: 3, vx: 25)
        var high = ElevenMatchEngine(scenario: state)
        high.step(input: ElevenInput(), dt: 0.05)
        check(high.leftScore == 0 && high.restartLabel == "골킥", "above bar is not goal")
        state.ball = FootballBall(x: 52, y: 67.9, vy: 15)
        var touchline = ElevenMatchEngine(scenario: state)
        touchline.step(input: ElevenInput(), dt: 0.05)
        check(touchline.ball.carrier == .right && touchline.kickoffFor > 0, "touchline ownership not wall bounce")
        check(touchline.ball.throwIn && touchline.ball.heldBy != nil && touchline.ball.z > 1.5,
              "throw-in held above head outside touchline")
        if let thrower = touchline.ball.heldBy { check(touchline.players[thrower].y > 68, "thrower stands outside field") }
        touchline.step(input: ElevenInput(), dt: 1.2)
        touchline.pass(side: .right)
        touchline.step(input: ElevenInput(), dt: 0.6)
        check(!touchline.ball.throwIn && touchline.ball.heldBy == nil && touchline.ball.y < 68 && touchline.ball.z > 1,
              "throw-in releases over head into field without retriggering boundary")
        state = base.snapshot
        state.ball = FootballBall(x: 4.5, y: 34, z: 1.1, vx: -6)
        var keeper = ElevenMatchEngine(scenario: state)
        keeper.step(input: ElevenInput(), dt: 0.2)
        check(keeper.ball.heldBy == 0 && keeper.selectedID == 0, "keeper catches with hands and becomes selected")
        keeper.pass()
        keeper.step(input: ElevenInput(), dt: 0.5)
        check(keeper.ball.heldBy == nil && keeper.ball.vx > 0 && keeper.ball.z > 1, "keeper throws to teammate")
        state.ball = FootballBall(x: 10, y: 35.4, z: 0.8, vx: -22)
        var diving = ElevenMatchEngine(scenario: state)
        diving.step(input: ElevenInput(), dt: 0.1)
        check(diving.players[0].action?.kind == .dive, "keeper anticipates and dives across goal")
        state = base.snapshot
        state.players[9].x = 50; state.players[9].y = 34
        state.players[20].x = 51.25; state.players[20].y = 34
        state.ball = FootballBall(x: 51, y: 34, carrier: .right)
        var tackle = ElevenMatchEngine(scenario: state)
        var standing = ElevenMatchEngine(scenario: state)
        standing.tackle(sliding: false); standing.step(input: ElevenInput(), dt: 0.2)
        check(standing.players[20].fallenFor == 0 && standing.ball.carrier != .right, "standing tackle pokes ball without forced fall")
        tackle.tackle(); tackle.step(input: ElevenInput(), dt: 0.22)
        check(tackle.players[20].fallenFor > 0 && tackle.ball.carrier == nil, "tackle contact knocks actual carrier")
        var distant = base
        distant.tackle(); distant.step(input: ElevenInput(), dt: 0.25)
        check(distant.players.allSatisfy { $0.fallenFor == 0 }, "no distant tackle knockdown")
        var remote = base
        remote.remoteControlled = true
        remote.step(input: ElevenInput(), dt: 1, remoteInput: ElevenInput(vertical: 1))
        check(remote.players[20].y > base.players[20].y && remote.players[9].y == base.players[9].y,
              "remote input only controls right team")
        let snapshot = remote.snapshot
        if let data = try? JSONEncoder().encode(snapshot),
           let decoded = try? JSONDecoder().decode(ElevenSnapshot.self, from: data) {
            check(decoded.valid && decoded.players[20].y == snapshot.players[20].y, "snapshot roundtrip")
        } else { check(false, "snapshot serialization") }
        let packet = ElevenPacket(kind: "snapshot", sequence: 10, snapshot: snapshot)
        if let wire = ElevenFraming.encode(packet) {
            var parser = ElevenFraming()
            do {
                check(try parser.append(Data(wire.prefix(2))).isEmpty, "fragmented prefix")
                check(try parser.append(Data(wire.dropFirst(2).prefix(11))).isEmpty, "fragmented body")
                let decoded = try parser.append(Data(wire.dropFirst(13)) + wire)
                check(decoded.count == 2 && decoded[0].snapshot?.valid == true, "coalesced packets")
            } catch { check(false, "frame parsing") }
        } else { check(false, "frame encoding") }
        var badParser = ElevenFraming()
        do { _ = try badParser.append(Data([0x7f, 0xff, 0xff, 0xff])); check(false, "oversize rejected") }
        catch { }
        var match = ElevenMatchEngine(duration: 300)
        for _ in 0..<20000 where !match.finished { match.step(input: ElevenInput(), dt: 1 / 60.0) }
        check(match.finished && match.snapshot.valid, "five minute AI match finishes with finite state")
        return failures
    }
}
