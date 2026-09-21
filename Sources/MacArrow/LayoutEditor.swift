import AppKit

@MainActor
final class LayoutEditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var layout: ScreenLayout
    private let canvas: LayoutCanvasView
    private let nameField = NSTextField()
    private let hostField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var selectedID: UUID?

    private let terminateOnClose: Bool

    init(layout: ScreenLayout, terminateOnClose: Bool = true) {
        self.layout = layout
        self.terminateOnClose = terminateOnClose
        self.canvas = LayoutCanvasView(layout: layout)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "mac-arrow 화면 배치"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI(in: window.contentView!)
        canvas.onSelectionChanged = { [weak self] id in self?.select(id) }
        canvas.onLayoutChanged = { [weak self] updated in self?.layout = updated }
        select(layout.screens.first?.id)
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI(in root: NSView) {
        let title = NSTextField(labelWithString: "화면을 실제 위치처럼 드래그하세요")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 478, width: 560, height: 24)
        root.addSubview(title)

        let subtitle = NSTextField(labelWithString: "예: 친구 화면이 내 왼쪽이면, 친구 카드를 내 화면 왼쪽에 놓습니다.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 452, width: 620, height: 20)
        root.addSubview(subtitle)

        canvas.frame = NSRect(x: 24, y: 68, width: 590, height: 370)
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 12
        canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(canvas)

        let panel = NSBox(frame: NSRect(x: 634, y: 68, width: 202, height: 370))
        panel.title = "선택한 화면"
        root.addSubview(panel)

        addLabel("이름", x: 16, y: 302, to: panel)
        nameField.frame = NSRect(x: 16, y: 274, width: 168, height: 24)
        panel.addSubview(nameField)

        addLabel("호스트명 또는 IP", x: 16, y: 238, to: panel)
        hostField.frame = NSRect(x: 16, y: 210, width: 168, height: 24)
        hostField.placeholderString = "friends-mac.local"
        panel.addSubview(hostField)

        let applyButton = NSButton(title: "정보 적용", target: self, action: #selector(applyFields))
        applyButton.frame = NSRect(x: 16, y: 168, width: 168, height: 30)
        panel.addSubview(applyButton)

        let addButton = NSButton(title: "+ 친구 화면 추가", target: self, action: #selector(addScreen))
        addButton.frame = NSRect(x: 16, y: 116, width: 168, height: 30)
        panel.addSubview(addButton)

        let removeButton = NSButton(title: "선택 화면 삭제", target: self, action: #selector(removeScreen))
        removeButton.frame = NSRect(x: 16, y: 78, width: 168, height: 30)
        panel.addSubview(removeButton)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 16, y: 20, width: 168, height: 40)
        panel.addSubview(statusLabel)

        let saveButton = NSButton(title: "저장", target: self, action: #selector(saveAndClose))
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 716, y: 20, width: 120, height: 34)
        root.addSubview(saveButton)
    }

    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 168, height: 20)
        view.addSubview(label)
    }

    private func select(_ id: UUID?) {
        selectedID = id
        canvas.selectedID = id
        guard let screen = layout.screens.first(where: { $0.id == id }) else {
            nameField.stringValue = ""
            hostField.stringValue = ""
            return
        }
        nameField.stringValue = screen.name
        hostField.stringValue = screen.host
        hostField.isEnabled = !screen.isLocal
        statusLabel.stringValue = screen.isLocal ? "이 화면은 내 Mac입니다" : "발사 대상 화면"
    }

    @objc private func applyFields() {
        guard let id = selectedID,
              let index = layout.screens.firstIndex(where: { $0.id == id }) else { return }
        layout.screens[index].name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !layout.screens[index].isLocal {
            layout.screens[index].host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        canvas.layout = layout
        statusLabel.stringValue = "적용됨"
    }

    @objc private func addScreen() {
        let number = layout.screens.count + 1
        let local = layout.screens.first(where: \.isLocal)
        let screen = PeerScreen(
            id: UUID(),
            name: "\(number) 친구",
            host: "",
            x: (local?.x ?? 260) - Double(number * 45),
            y: (local?.y ?? 170) + Double((number - 2) * 40),
            isLocal: false
        )
        layout.screens.append(screen)
        canvas.layout = layout
        select(screen.id)
    }

    @objc private func removeScreen() {
        guard let id = selectedID,
              layout.screens.first(where: { $0.id == id })?.isLocal == false else {
            statusLabel.stringValue = "내 화면은 삭제할 수 없습니다"
            return
        }
        layout.screens.removeAll { $0.id == id }
        canvas.layout = layout
        select(layout.screens.first?.id)
    }

    @objc private func saveAndClose() {
        applyFields()
        do {
            try ScreenLayoutStore.save(layout)
            statusLabel.stringValue = "저장됨"
            window?.close()
        } catch {
            statusLabel.stringValue = "저장 실패: \(error.localizedDescription)"
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        if terminateOnClose {
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
private final class LayoutCanvasView: NSView {
    var layout: ScreenLayout { didSet { needsDisplay = true } }
    var selectedID: UUID? { didSet { needsDisplay = true } }
    var onSelectionChanged: ((UUID?) -> Void)?
    var onLayoutChanged: ((ScreenLayout) -> Void)?
    private var draggingID: UUID?
    private var dragOffset = CGPoint.zero
    private let cardSize = CGSize(width: 160, height: 96)

    init(layout: ScreenLayout) {
        self.layout = layout
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        let grid = NSBezierPath()
        stride(from: 20.0, to: Double(bounds.width), by: 40).forEach {
            grid.move(to: CGPoint(x: $0, y: 0)); grid.line(to: CGPoint(x: $0, y: bounds.height))
        }
        stride(from: 20.0, to: Double(bounds.height), by: 40).forEach {
            grid.move(to: CGPoint(x: 0, y: $0)); grid.line(to: CGPoint(x: bounds.width, y: $0))
        }
        grid.lineWidth = 0.5
        grid.stroke()

        for screen in layout.screens {
            let rect = cardRect(for: screen)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            (screen.isLocal ? NSColor.systemBlue : NSColor.controlAccentColor.withAlphaComponent(0.72)).setFill()
            path.fill()
            if screen.id == selectedID {
                NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
            NSString(string: screen.name).draw(in: rect.insetBy(dx: 8, dy: 28), withAttributes: attributes)
            let host = screen.isLocal ? "내 Mac" : (screen.host.isEmpty ? "호스트 미입력" : screen.host)
            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                .paragraphStyle: paragraph
            ]
            NSString(string: host).draw(in: NSRect(x: rect.minX + 8, y: rect.minY + 12, width: rect.width - 16, height: 18), withAttributes: detailAttributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let screen = layout.screens.reversed().first(where: { cardRect(for: $0).contains(point) }) else {
            onSelectionChanged?(nil); return
        }
        draggingID = screen.id
        dragOffset = CGPoint(x: point.x - CGFloat(screen.x), y: point.y - CGFloat(screen.y))
        onSelectionChanged?(screen.id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = draggingID,
              let index = layout.screens.firstIndex(where: { $0.id == id }) else { return }
        let point = convert(event.locationInWindow, from: nil)
        layout.screens[index].x = Double(min(max(point.x - dragOffset.x, 0), bounds.width - cardSize.width))
        layout.screens[index].y = Double(min(max(point.y - dragOffset.y, 0), bounds.height - cardSize.height))
        onLayoutChanged?(layout)
    }

    override func mouseUp(with event: NSEvent) { draggingID = nil }

    private func cardRect(for screen: PeerScreen) -> NSRect {
        NSRect(x: screen.x, y: screen.y, width: cardSize.width, height: cardSize.height)
    }
}
