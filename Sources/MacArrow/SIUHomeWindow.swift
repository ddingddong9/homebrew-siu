import AppKit

/// The one-on-one front door. Networking remains owned by MenuBarController.
@MainActor
final class SIUHomeWindowController: NSWindowController {
    var onCreate: (() -> Void)?
    var onJoin: (() -> Void)?
    var onStart: (() -> Void)?
    var onPractice: (() -> Void)?
    var onSettings: (() -> Void)?
    var onLeave: (() -> Void)?
    var onDoubles: (() -> Void)?
    var onTeam: ((FootballTeam) -> Void)?
    private let teamChoice = NSSegmentedControl(labels:["호날두팀","메시팀"],trackingMode:.selectOne,target:nil,action:nil)
    private let teamStatus = NSTextField(labelWithString:"진영 선택 · 서로 반대 팀으로 경기합니다")
    private let status = NSTextField(wrappingLabelWithString: "같은 와이파이의 친구와 경기를 준비하세요.")
    private var startButton: NSButton!
    private var leaveButton: NSButton!

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SIU · 1대1"
        window.minSize = NSSize(width: 1000, height: 740)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.07, blue: 0.12, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        let root = SIUStadiumView()
        window.contentView = root

        func label(_ text: String, size: CGFloat, color: NSColor = .white) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: size, weight: .semibold)
            field.textColor = color
            field.translatesAutoresizingMaskIntoConstraints = false
            return field
        }
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.08, blue: 0.22, alpha: 0.96).cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        let brand = label("SIU", size: 30)
        let subtitle = label("PLAY TOGETHER  /  1대1 축구", size: 12, color: .systemTeal)
        let home = label("홈     /     친구 대전     /     트레이닝", size: 13)
        [brand, subtitle, home].forEach { header.addSubview($0) }

        let menu = NSStackView()
        menu.orientation = .vertical
        menu.alignment = .leading
        menu.spacing = 12
        menu.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(menu)
        menu.addArrangedSubview(label("KICK OFF", size: 11, color: .systemTeal))
        menu.addArrangedSubview(label("오늘도, 한 경기.", size: 30))
        menu.addArrangedSubview(label("친구와 함께하는 SIU 1대1", size: 13, color: .lightGray))
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 18).isActive = true
        menu.addArrangedSubview(spacer)
        func button(_ title: String, action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.alignment = .left
            b.font = .systemFont(ofSize: 17, weight: .semibold)
            b.contentTintColor = .white
            b.wantsLayer = true
            b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
            b.layer?.cornerRadius = 8
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 260).isActive = true
            b.heightAnchor.constraint(equalToConstant: 52).isActive = true
            menu.addArrangedSubview(b)
            return b
        }
        _ = button("  ＋   방 만들기", action: #selector(create))
        _ = button("  →   방 참가", action: #selector(join))
        _ = button("  ⚽   AI 연습", action: #selector(practice))
        _ = button("  2×2   4인 LAN 대전", action: #selector(doubles))
        _ = button("  ⚙   설정", action: #selector(settings))
        _ = button("  ?   조작 안내", action: #selector(controls))
        leaveButton = button("  ↩   방 나가기", action: #selector(leave))

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.07, blue: 0.15, alpha: 0.92).cgColor
        card.layer?.cornerRadius = 14
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        card.layer?.borderWidth = 1
        root.addSubview(card)
        teamChoice.target = self; teamChoice.action = #selector(chooseTeam)
        teamChoice.selectedSegment = 0
        teamChoice.translatesAutoresizingMaskIntoConstraints = false
        teamStatus.translatesAutoresizingMaskIntoConstraints = false
        teamStatus.font = .systemFont(ofSize:12); teamStatus.textColor = .white
        root.addSubview(teamChoice); root.addSubview(teamStatus)
        let portraits = NSStackView(); portraits.orientation = .horizontal; portraits.distribution = .fillEqually
        portraits.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(portraits)
        for image in [ResourceBundle.images.url(forResource:"move-01",withExtension:"png").flatMap(NSImage.init(contentsOf:)),MessiSprites.shared.image()] {
            let view = NSImageView(); view.image = image; view.imageScaling = .scaleProportionallyUpOrDown; portraits.addArrangedSubview(view)
        }
        let title = label("FRIEND MATCH", size: 12, color: .systemTeal)
        let heading = label("친구와 1대1", size: 24)
        status.textColor = .white
        status.font = .systemFont(ofSize: 13)
        status.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(wrappingLabelWithString: "같은 와이파이 → 방 참가 승인 → 경기 시작\n두 Mac에서 같은 버전을 사용하세요.")
        hint.textColor = .lightGray
        hint.font = .systemFont(ofSize: 12)
        hint.translatesAutoresizingMaskIntoConstraints = false
        startButton = NSButton(title: "경기 시작  →", target: self, action: #selector(start))
        startButton.bezelStyle = .rounded
        startButton.contentTintColor = .systemTeal
        startButton.translatesAutoresizingMaskIntoConstraints = false
        [title, heading, status, hint, startButton].forEach { card.addSubview($0) }
        let footer = label("SIU ONE ON ONE    •    LOCAL NETWORK PLAY", size: 11, color: .lightGray)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 82),
            brand.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 36), brand.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            subtitle.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 24), subtitle.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            home.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -36), home.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            menu.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 38), menu.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 40),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32), card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 42),
            card.widthAnchor.constraint(equalToConstant: 284), card.heightAnchor.constraint(equalToConstant: 270),
            teamStatus.topAnchor.constraint(equalTo:card.bottomAnchor,constant:24), teamStatus.leadingAnchor.constraint(equalTo:card.leadingAnchor),
            teamChoice.topAnchor.constraint(equalTo:teamStatus.bottomAnchor,constant:12),teamChoice.leadingAnchor.constraint(equalTo:card.leadingAnchor),teamChoice.widthAnchor.constraint(equalTo:card.widthAnchor),
            portraits.topAnchor.constraint(equalTo:teamChoice.bottomAnchor,constant:12),portraits.leadingAnchor.constraint(equalTo:card.leadingAnchor),portraits.widthAnchor.constraint(equalTo:card.widthAnchor),portraits.heightAnchor.constraint(equalToConstant:115),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22), title.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            heading.leadingAnchor.constraint(equalTo: title.leadingAnchor), heading.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor), status.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            status.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18), status.heightAnchor.constraint(equalToConstant: 44),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor), hint.trailingAnchor.constraint(equalTo: status.trailingAnchor), hint.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10),
            startButton.leadingAnchor.constraint(equalTo: title.leadingAnchor), startButton.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            startButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20), startButton.heightAnchor.constraint(equalToConstant: 36),
            footer.leadingAnchor.constraint(equalTo: menu.leadingAnchor), footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func update(status text: String, canStart: Bool, inRoom: Bool) {
        status.stringValue = text
        startButton.isEnabled = canStart
        leaveButton.isEnabled = inRoom
    }
    func updateTeam(_ team: FootballTeam, inRoom: Bool) {
        teamChoice.selectedSegment = team.rawValue; teamChoice.isEnabled = inRoom
        teamStatus.stringValue = inRoom ? "나: \(team.title) · 상대: \(team.opposite.title)" : "방을 만들거나 참가하면 진영 선택 가능"
    }
    @objc private func chooseTeam() { if let team = FootballTeam(rawValue:teamChoice.selectedSegment) { onTeam?(team) } }
    @objc private func create() { onCreate?() }
    @objc private func join() { onJoin?() }
    @objc private func start() { onStart?() }
    @objc private func practice() { onPractice?() }
    @objc private func doubles() { onDoubles?() }
    @objc private func settings() { onSettings?() }
    @objc private func leave() { onLeave?() }
    @objc private func controls() {
        let alert = NSAlert()
        alert.messageText = "SIU 조작 안내"
        alert.informativeText = "방 대기 중 호날두팀·메시팀을 선택하세요. 1대1은 서로 반대 팀, 2대2는 팀당 2명이며 선택 시 상대 슬롯과 교환합니다.\n\n2대2: 방향키 이동 / E 스태미나 달리기 / D 슛 / S 동료 패스 / W 스루패스 / A 슬라이딩 태클 / Z+D 커브슛\n개인기: Shift+Q 백숏 / Shift+E 발재간 / Shift+X 사포 / Shift+A 팬텀\nShift 조합은 SIU 간소화 키로 FC온라인의 정확한 개인기 입력과 다릅니다. Esc: 방장 일시정지\n\n1대1: Shift 스태미나 달리기 / D 슛 / A 태클 / S 사포 / X 팬텀 / Z 턴 / E 발재간 / Q 백숏\n메시: 기본·슛·태클·팬텀 원본 누끼. 자료가 없는 동작은 메시 기본 자세와 공 효과를 사용합니다.\n\n2대2: 4인 LAN 대전 → 방 만들기 → 다른 3명 참가 → 진영 선택 → 4인 경기 시작. 모두 같은 버전 필요."
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}

/// Code-drawn stadium: no external art or FC assets are distributed.
@MainActor
private final class SIUStadiumView: NSView {
    private let player = ResourceBundle.images.url(forResource: "move-01", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor(calibratedRed: 0.06, green: 0.14, blue: 0.23, alpha: 1),
                            NSColor(calibratedRed: 0.16, green: 0.29, blue: 0.22, alpha: 1)])?.draw(in: bounds, angle: -90)
        let w = bounds.width, h = bounds.height
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            let width = w * (0.68 + y * 0.25)
            return NSPoint(x: w * 0.64 + (x - 0.5) * width, y: h * (0.10 + y * 0.69))
        }
        func polygon(_ points: [NSPoint], color: NSColor, stroke: Bool = false) {
            let path = NSBezierPath()
            path.move(to: points[0]); points.dropFirst().forEach { path.line(to: $0) }; path.close()
            color.set()
            if stroke { path.lineWidth = 2; path.stroke() } else { path.fill() }
        }
        // Seating banks and deterministic crowd dots.
        for row in 0..<7 {
            let y = h * 0.81 + CGFloat(row) * 10
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSRect(x: 300, y: y, width: w, height: 2).fill()
            for seat in 0..<70 {
                let x = CGFloat(seat) * 17 + 310 + CGFloat(row % 2) * 6
                NSColor(calibratedWhite: 0.6, alpha: CGFloat((seat + row) % 3 + 1) * 0.1).setFill()
                NSRect(x: x, y: y + 4, width: 3, height: 3).fill()
            }
        }
        polygon([point(-0.04, -0.04), point(1.04, -0.04), point(1.04, 1.04), point(-0.04, 1.04)],
                color: NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.15, alpha: 1))
        for band in 0..<12 {
            let x = CGFloat(band) / 12
            polygon([point(x, 0), point(x + 1/12, 0), point(x + 1/12, 1), point(x, 1)],
                    color: NSColor(calibratedRed: band % 2 == 0 ? 0.22 : 0.25, green: band % 2 == 0 ? 0.40 : 0.45, blue: 0.18, alpha: 1))
        }
        let line = NSColor.white.withAlphaComponent(0.6)
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            polygon([point(x,y), point(x+width,y), point(x+width,y+height), point(x,y+height)], color: line, stroke: true)
        }
        box(0,0,1,1); box(0,0.28,0.16,0.44); box(0.84,0.28,0.16,0.44)
        box(0,0.40,0.055,0.20); box(0.945,0.40,0.055,0.20)
        let middle = NSBezierPath(); middle.move(to: point(0.5,0)); middle.line(to: point(0.5,1)); line.setStroke(); middle.lineWidth = 2; middle.stroke()
        let circle = NSBezierPath()
        for i in 0...80 {
            let a = CGFloat(i) / 80 * .pi * 2
            let p = point(0.5 + cos(a)*0.095, 0.5 + sin(a)*0.14)
            if i == 0 { circle.move(to:p) } else { circle.line(to:p) }
        }
        circle.stroke()
        box(0.995,0.43,0.025,0.14)
        let position = point(0.48,0.35)
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: position.x-20, y:position.y-4, width:40,height:12)).fill()
        player?.draw(in: NSRect(x: position.x-34,y:position.y,width:68,height:82))
        NSColor.white.setFill()
        NSBezierPath(ovalIn:NSRect(x:position.x+27,y:position.y-2,width:11,height:11)).fill()
        NSGradient(starting: NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.095, alpha: 0.98),
                   ending: .clear)?.draw(in: bounds, angle: 0)
    }
}
