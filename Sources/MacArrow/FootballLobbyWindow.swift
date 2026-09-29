import AppKit

@MainActor
final class FootballLobbyWindowController: NSWindowController, NSWindowDelegate {
    private let session = FootballLobbySession()
    private let statusLabel = NSTextField(labelWithString: "")
    private let roomPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let startButton = NSButton()
    private var game: Process?

    init() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 670)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "SIU Football · 11대11"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildInterface(in: window)
        session.onChange = { [weak self] in self?.refresh() }
        session.onStart = { [weak self] host, address, port in
            self?.launchGame(role: host ? "host" : "client", address: address, port: port) ?? false
        }
        session.approve = { [weak self] peer in
            let alert = NSAlert()
            alert.messageText = "파랑 팀 참가 요청"
            alert.informativeText = "접속 기기: \(peer)\n같이 경기할 친구인지 확인하세요."
            alert.addButton(withTitle: "참가 허용")
            alert.addButton(withTitle: "거절")
            self?.window?.makeKeyAndOrderFront(nil)
            return alert.runModal() == .alertFirstButtonReturn
        }
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        session.stop()
        game?.terminate()
        NSApplication.shared.terminate(nil)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildInterface(in window: NSWindow) {
        let canvas = NSView(frame: window.contentView!.bounds)
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(srgbRed: 0.035, green: 0.075, blue: 0.11, alpha: 1).cgColor
        window.contentView = canvas

        label("SIU  /  ELEVEN", frame: NSRect(x: 64, y: 552, width: 660, height: 70),
              size: 50, weight: .heavy, color: .white, parent: canvas)
        label("두 Mac · 두 팀 · 하나의 경기", frame: NSRect(x: 66, y: 516, width: 650, height: 30),
              size: 19, weight: .medium, color: NSColor(srgbRed: 0.68, green: 0.79, blue: 0.83, alpha: 1), parent: canvas)
        label("같은 Wi-Fi에서 방을 만들거나 찾아 참가하세요.",
              frame: NSRect(x: 66, y: 475, width: 730, height: 25),
              size: 14, weight: .regular, color: .lightGray, parent: canvas)

        let hostCard = card(NSRect(x: 60, y: 205, width: 425, height: 238),
                            color: NSColor(srgbRed: 0.30, green: 0.09, blue: 0.12, alpha: 1), parent: canvas)
        label("01  빨강 팀  ·  방장", frame: NSRect(x: 25, y: 175, width: 370, height: 38),
              size: 25, weight: .bold, color: NSColor(srgbRed: 1, green: 0.76, blue: 0.71, alpha: 1), parent: hostCard)
        label("방을 만들고 친구 참가를 허용한 뒤 시작", frame: NSRect(x: 26, y: 133, width: 370, height: 25),
              size: 14, weight: .regular, color: .white, parent: hostCard)
        button("방 만들기", frame: NSRect(x: 25, y: 67, width: 174, height: 45),
               color: NSColor(srgbRed: 0.82, green: 0.22, blue: 0.26, alpha: 1),
               action: #selector(host), parent: hostCard)
        styleButton(startButton, title: "경기 시작", frame: NSRect(x: 216, y: 67, width: 178, height: 45),
                    color: NSColor(srgbRed: 0.54, green: 0.16, blue: 0.20, alpha: 1), action: #selector(start), parent: hostCard)

        let guestCard = card(NSRect(x: 515, y: 205, width: 425, height: 238),
                             color: NSColor(srgbRed: 0.075, green: 0.17, blue: 0.34, alpha: 1), parent: canvas)
        label("02  파랑 팀  ·  참가자", frame: NSRect(x: 25, y: 175, width: 370, height: 38),
              size: 25, weight: .bold, color: NSColor(srgbRed: 0.67, green: 0.84, blue: 1, alpha: 1), parent: guestCard)
        label("방을 찾고 선택한 뒤 방장 승인을 기다리기", frame: NSRect(x: 26, y: 133, width: 380, height: 25),
              size: 14, weight: .regular, color: .white, parent: guestCard)
        roomPicker.frame = NSRect(x: 25, y: 93, width: 369, height: 30)
        guestCard.addSubview(roomPicker)
        button("방 검색", frame: NSRect(x: 25, y: 31, width: 174, height: 45),
               color: NSColor(srgbRed: 0.18, green: 0.42, blue: 0.79, alpha: 1),
               action: #selector(browse), parent: guestCard)
        button("참가", frame: NSRect(x: 216, y: 31, width: 178, height: 45),
               color: NSColor(srgbRed: 0.14, green: 0.32, blue: 0.61, alpha: 1),
               action: #selector(join), parent: guestCard)

        button("AI 상대 로컬 연습", frame: NSRect(x: 60, y: 126, width: 240, height: 45),
               color: NSColor(srgbRed: 0.12, green: 0.38, blue: 0.28, alpha: 1),
               action: #selector(practice), parent: canvas)
        button("방 나가기", frame: NSRect(x: 320, y: 126, width: 155, height: 45),
               color: NSColor(srgbRed: 0.18, green: 0.24, blue: 0.30, alpha: 1),
               action: #selector(leave), parent: canvas)
        statusLabel.frame = NSRect(x: 60, y: 65, width: 880, height: 36)
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = .white
        canvas.addSubview(statusLabel)
        label("개발용 LAN 알파 · 키보드: 방향키 이동, E 질주, S 패스, D 슛 · Esc 경기 메뉴",
              frame: NSRect(x: 60, y: 30, width: 890, height: 24),
              size: 12, weight: .regular, color: .lightGray, parent: canvas)
    }

    private func label(_ text: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight,
                       color: NSColor, parent: NSView) {
        let view = NSTextField(labelWithString: text)
        view.frame = frame; view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = color
        parent.addSubview(view)
    }

    private func card(_ frame: NSRect, color: NSColor, parent: NSView) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = 18
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        parent.addSubview(view)
        return view
    }

    @discardableResult
    private func button(_ title: String, frame: NSRect, color: NSColor, action: Selector, parent: NSView) -> NSButton {
        let button = NSButton()
        styleButton(button, title: title, frame: frame, color: color, action: action, parent: parent)
        return button
    }

    private func styleButton(_ button: NSButton, title: String, frame: NSRect,
                             color: NSColor, action: Selector, parent: NSView) {
        button.title = title; button.frame = frame; button.target = self; button.action = action
        button.isBordered = false; button.wantsLayer = true
        button.layer?.backgroundColor = color.cgColor
        button.layer?.cornerRadius = 10
        button.font = .systemFont(ofSize: 16, weight: .bold)
        button.contentTintColor = .white
        parent.addSubview(button)
    }

    private func refresh() {
        statusLabel.stringValue = session.status
        let selected = roomPicker.titleOfSelectedItem
        roomPicker.removeAllItems()
        roomPicker.addItems(withTitles: session.rooms.map(\.name))
        if let selected { roomPicker.selectItem(withTitle: selected) }
        startButton.isEnabled = session.role == .host && session.connected && game == nil
        roomPicker.isEnabled = !session.rooms.isEmpty
    }

    @objc private func host() {
        let alert = NSAlert()
        alert.messageText = "SIU 방 만들기"
        alert.informativeText = "방 이름과 경기에서 사용할 내 팀 이름을 입력하세요."
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 82))
        let teamLabel = NSTextField(labelWithString: "내 팀 이름 (최대 20자)")
        teamLabel.frame = NSRect(x: 0, y: 34, width: 300, height: 20)
        fields.addSubview(teamLabel)
        let team = NSTextField(string: UserDefaults.standard.string(forKey: "siuFootballTeamName") ?? "SIU")
        team.frame = NSRect(x: 0, y: 8, width: 300, height: 26)
        fields.addSubview(team)
        let name = NSTextField(string: "\(Host.current().localizedName ?? "SIU")의 방")
        name.frame = NSRect(x: 0, y: 58, width: 300, height: 26)
        fields.addSubview(name)
        alert.accessoryView = fields
        alert.addButton(withTitle: "방 만들기"); alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn {
            guard let teamName = validatedTeamName(team.stringValue) else { return }
            UserDefaults.standard.set(teamName, forKey: "siuFootballTeamName")
            do { try session.host(name: name.stringValue.isEmpty ? "SIU 방" : name.stringValue,
                                  teamName: teamName) }
            catch { statusLabel.stringValue = "방 생성 실패: \(error.localizedDescription)" }
        }
    }
    @objc private func browse() { session.browse() }
    @objc private func join() {
        guard roomPicker.indexOfSelectedItem >= 0, let teamName = askTeamName() else { return }
        session.join(index: roomPicker.indexOfSelectedItem, teamName: teamName)
    }
    @objc private func start() { _ = session.startMatch() }
    @objc private func leave() { session.stop() }
    @objc private func practice() {
        guard let teamName = askTeamName() else { return }
        _ = launchGame(role: "offline", address: "", port: 38245, practiceTeamName: teamName)
    }

    private func validatedTeamName(_ input: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20,
              name.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" }) else {
            statusLabel.stringValue = "팀 이름은 1~20자의 글자·숫자·공백·하이픈만 사용할 수 있습니다"
            return nil
        }
        return name
    }

    private func askTeamName() -> String? {
        let alert = NSAlert()
        alert.messageText = "경기 전 내 팀 이름"
        alert.informativeText = "친구의 화면과 경기 점수판에 표시됩니다."
        let field = NSTextField(string: UserDefaults.standard.string(forKey: "siuFootballTeamName") ?? "SIU")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 26)
        alert.accessoryView = field
        alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn,
              let name = validatedTeamName(field.stringValue) else { return nil }
        UserDefaults.standard.set(name, forKey: "siuFootballTeamName")
        return name
    }

    private func launchGame(role: String, address: String, port: UInt16,
                            practiceTeamName: String? = nil) -> Bool {
        guard game == nil, let bundle = Bundle.main.resourceURL else { return false }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/gameplayfootball")
        let sourceConfig = bundle.appendingPathComponent("football.config")
        guard let original = try? String(contentsOf: sourceConfig) else {
            statusLabel.stringValue = "경기 설정을 읽을 수 없습니다"
            return false
        }
        let baseConfig = original.split(separator: "\n").filter {
            !["\"debug\"", "\"font_filename\"", "\"siu_lan_role\"", "\"siu_lan_host\"", "\"siu_lan_port\""].contains($0.split(separator: " ").first.map(String.init) ?? "")
        }.joined(separator: "\n")
        let homeName = practiceTeamName ?? session.homeTeamName
        let awayName = role == "offline" ? "AI" : session.awayTeamName
        let koreanFont = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
        let needsKoreanFont = (homeName + awayName).unicodeScalars.contains { !$0.isASCII }
        let fontConfig = needsKoreanFont && FileManager.default.fileExists(atPath: koreanFont)
            ? "\"font_filename\" \"\(koreanFont)\"\n" : ""
        let configuration = baseConfig + "\n\"debug\" \"true\"\n" +
            fontConfig +
            "\"siu_lan_role\" \"\(role == "offline" ? "" : role)\"\n" +
            "\"siu_lan_host\" \"\(address)\"\n\"siu_lan_port\" \"\(port)\"\n" +
            "\"siu_home_team_name\" \"\(homeName)\"\n" +
            "\"siu_away_team_name\" \"\(awayName)\"\n" +
            "\"siu_home_team_short_name\" \"\(String(homeName.prefix(3)))\"\n" +
            "\"siu_away_team_short_name\" \"\(String(awayName.prefix(3)))\"\n"
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("siu-football-\(UUID().uuidString).config")
        do {
            try configuration.write(to: configURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = executable
            process.arguments = [configURL.path]
            process.currentDirectoryURL = bundle
            process.terminationHandler = { [weak self] _ in
                try? FileManager.default.removeItem(at: configURL)
                DispatchQueue.main.async {
                    self?.game = nil
                    self?.window?.makeKeyAndOrderFront(nil)
                    self?.refresh()
                }
            }
            try process.run()
            game = process
            window?.orderOut(nil)
            // The SDL match is a separate process. Without making it active,
            // macOS can keep keyboard focus on the hidden lobby window.
            NSRunningApplication(processIdentifier: process.processIdentifier)?
                .activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard self.game === process else { return }
                NSRunningApplication(processIdentifier: process.processIdentifier)?
                    .activate(options: [.activateAllWindows])
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: configURL)
            statusLabel.stringValue = "경기 실행 실패: \(error.localizedDescription)"
            return false
        }
    }
}
