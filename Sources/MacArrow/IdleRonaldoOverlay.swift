import AppKit

enum IdleIconPlacement {
    static func frame(in visible: CGRect, size: CGSize = CGSize(width:112,height:112),
                      unitX: Double, unitY: Double) -> CGRect {
        let width = min(size.width,max(0,visible.width)), height = min(size.height,max(0,visible.height))
        return CGRect(x:visible.minX + max(0,visible.width-width)*min(1,max(0,unitX)),
                      y:visible.minY + max(0,visible.height-height)*min(1,max(0,unitY)),width:width,height:height)
    }
}

/// A single transparent, click-through mascot. Never takes keyboard focus.
@MainActor
final class IdleRonaldoOverlay {
    var isPlaying: (() -> Bool)?
    private let panel: NSPanel
    private var timer: Timer?
    private var nextMove: TimeInterval = 0
    init() {
        panel = NSPanel(contentRect:NSRect(x:0,y:0,width:112,height:112),
                        styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = "SIU — 대기 호날두"
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        let image = NSImageView(frame:panel.contentView?.bounds ?? .zero)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.autoresizingMask = [.width,.height]
        image.image = Bundle.main.url(forResource:"siu",withExtension:"icns").flatMap(NSImage.init(contentsOf:)) ??
            ResourceBundle.images.url(forResource:"siu-character",withExtension:"png").flatMap(NSImage.init(contentsOf:))
        panel.contentView = image
    }
    func start() {
        guard timer == nil else { return }
        refresh()
        // Show for one second, hide for one second; each reappearance picks a new position.
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func refresh() {
        let enabled = UserDefaults.standard.object(forKey:"SIUIdleRonaldoEnabled") as? Bool ?? true
        guard enabled, isPlaying?() != true, let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.orderOut(nil); nextMove = 0; return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextMove else { return }
        if panel.isVisible { panel.orderOut(nil); nextMove = now + 1; return }
        var frame = IdleIconPlacement.frame(in:screen.visibleFrame,unitX:Double.random(in:0...1),unitY:Double.random(in:0...1))
        for _ in 0..<8 where panel.isVisible && hypot(frame.midX-panel.frame.midX,frame.midY-panel.frame.midY) < 120 {
            frame = IdleIconPlacement.frame(in:screen.visibleFrame,unitX:Double.random(in:0...1),unitY:Double.random(in:0...1))
        }
        panel.setFrame(frame,display:true); panel.orderFrontRegardless(); nextMove = now + 1
    }
}
