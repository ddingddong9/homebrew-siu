import AppKit

enum SpecialMove: String, CaseIterable {
    case celebration, stepover, backheel

    var frameCount: Int {
        switch self { case .celebration: return 19; case .stepover: return 43; case .backheel: return 9 }
    }
    var duration: TimeInterval {
        switch self { case .celebration: return 2.1; case .stepover: return 1.0; case .backheel: return 0.65 }
    }
    func frameIndex(at elapsed: TimeInterval) -> Int? {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return nil }
        return min(frameCount - 1, Int(elapsed / duration * Double(frameCount)))
    }
}

@MainActor
struct SpecialMoveAnimation {
    let move: SpecialMove
    let frames: [NSImage]
    init(_ move: SpecialMove) {
        self.move = move
        frames = (1...move.frameCount).compactMap { index in
            ResourceBundle.images.url(forResource: String(format: "%@-%02d", move.rawValue, index), withExtension: "png")
                .flatMap(NSImage.init(contentsOf:))
        }
    }
    func image(at elapsed: TimeInterval) -> NSImage? {
        guard frames.count == move.frameCount, let index = move.frameIndex(at: elapsed) else { return nil }
        return frames[index]
    }
}
