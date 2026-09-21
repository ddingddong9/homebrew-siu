import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let overlay: BallOverlayController
    private let port: UInt16
    private var player: PlayerWindowController?
    private var layoutEditor: LayoutEditorWindowController?
    private let playerMenuItem = NSMenuItem(title: "선수 생성", action: #selector(togglePlayer), keyEquivalent: "")

    init(overlay: BallOverlayController, port: UInt16) {
        self.overlay = overlay
        self.port = port
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.title = "⚽️"
        let menu = NSMenu()
        playerMenuItem.target = self
        menu.addItem(playerMenuItem)
        menu.addItem(NSMenuItem(title: "화면 배치…", action: #selector(openLayout), keyEquivalent: ","))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "모든 축구공 지우기", action: #selector(clearBalls), keyEquivalent: "k"))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "siu 종료", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu
    }

    @objc private func togglePlayer() {
        if player == nil {
            let controller = PlayerWindowController()
            controller.onKick = { [weak self] direction, y, power in
                self?.kick(direction: direction, normalizedY: y, power: power)
            }
            player = controller
            controller.show()
            playerMenuItem.title = "선수 숨기기"
        } else if let visible = player?.toggle() {
            playerMenuItem.title = visible ? "선수 숨기기" : "선수 생성"
        }
    }

    @objc private func openLayout() {
        if let layoutEditor {
            layoutEditor.showWindow(nil)
            layoutEditor.window?.orderFrontRegardless()
            return
        }
        let editor = LayoutEditorWindowController(layout: ScreenLayoutStore.load(), terminateOnClose: false)
        editor.onClose = { [weak self] in
            self?.player?.refreshLayout()
            self?.layoutEditor = nil
        }
        layoutEditor = editor
        editor.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func clearBalls() {
        overlay.clearAll()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func kick(direction: ShootDirection, normalizedY: Double, power: Double) {
        guard let target = ScreenLayoutStore.load().target(in: direction) else {
            statusItem.button?.title = "⚠️"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.statusItem.button?.title = "⚽️" }
            return
        }
        let edge = direction == .left ? "right" : "left"
        BallSender.send(to: target.host, port: port, normalizedY: normalizedY, entryEdge: edge) { [weak self] error in
            DispatchQueue.main.async {
                self?.statusItem.button?.title = error == nil ? "➶" : "⚠️"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.statusItem.button?.title = "⚽️" }
            }
        }
        _ = power
    }
}
