import AppKit

@MainActor
final class RoomBrowserWindowController: NSWindowController, NSWindowDelegate {
    var onJoin: ((LocalRoom) -> Void)?
    var onClose: (() -> Void)?
    private let browser = LocalRoomBrowser()
    private let statusLabel = NSTextField(labelWithString: "같은 와이파이의 방을 찾는 중…")
    private let stack = NSStackView()
    private let listContent = NSView(frame: NSRect(x: 0, y: 0, width: 394, height: 240))
    private var rooms: [LocalRoom] = []
    private var joining = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 350),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "SIU — 참가할 방 선택"
        window.center()
        super.init(window: window)
        window.delegate = self
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 350))
        window.contentView = root
        let title = NSTextField(labelWithString: "같은 와이파이의 방")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: 24, y: 305, width: 410, height: 28)
        root.addSubview(title)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: 278, width: 412, height: 22)
        root.addSubview(statusLabel)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 25, width: 412, height: 240))
        scroll.hasVerticalScroller = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = listContent.bounds.insetBy(dx: 4, dy: 4)
        listContent.addSubview(stack)
        scroll.documentView = listContent
        root.addSubview(scroll)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        browser.start(onChange: { [weak self] rooms in self?.updateRooms(rooms) },
                      onFailure: { [weak self] in
                          self?.statusLabel.stringValue = "방 검색 실패 · 로컬 네트워크 권한을 확인하세요"
                      })
    }

    func setStatus(_ message: String, allowSelection: Bool = false) {
        statusLabel.stringValue = message
        joining = !allowSelection
        for case let button as NSButton in stack.arrangedSubviews {
            button.isEnabled = allowSelection
        }
    }

    func windowWillClose(_ notification: Notification) {
        browser.cancel()
        onClose?()
    }

    private func updateRooms(_ updated: [LocalRoom]) {
        rooms = updated
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, room) in rooms.enumerated() {
            let button = NSButton(title: "⚽️  \(room.name)", target: self, action: #selector(selectRoom(_:)))
            button.tag = index
            button.alignment = .left
            button.frame = NSRect(x: 0, y: 0, width: 375, height: 34)
            button.isEnabled = !joining
            stack.addArrangedSubview(button)
        }
        let height = max(CGFloat(240), CGFloat(rooms.count) * 42 + 8)
        listContent.frame.size.height = height
        stack.frame = listContent.bounds.insetBy(dx: 4, dy: 4)
        if !joining {
            statusLabel.stringValue = rooms.isEmpty ? "열린 방이 없습니다. 친구에게 방을 만들어 달라고 하세요."
                : "참가할 방을 선택하세요 (\(rooms.count)개)"
        }
    }

    @objc private func selectRoom(_ sender: NSButton) {
        guard rooms.indices.contains(sender.tag), !joining else { return }
        setStatus("방장 승인 대기 중…")
        onJoin?(rooms[sender.tag])
    }
}
