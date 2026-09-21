import Foundation

enum ShootDirection: String, CaseIterable {
    case left
    case right
}

struct PeerScreen: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var host: String
    var x: Double
    var y: Double
    var isLocal: Bool
}

struct ScreenLayout: Codable, Equatable {
    var screens: [PeerScreen]

    static var initial: ScreenLayout {
        ScreenLayout(screens: [
            PeerScreen(id: UUID(), name: "1 나", host: "", x: 340, y: 180, isLocal: true),
            PeerScreen(id: UUID(), name: "2 친구", host: "friends-mac.local", x: 100, y: 180, isLocal: false)
        ])
    }

    func target(in direction: ShootDirection) -> PeerScreen? {
        guard let local = screens.first(where: \.isLocal) else { return nil }
        return screens
            .filter { screen in
                guard !screen.isLocal, !screen.host.isEmpty else { return false }
                return direction == .left ? screen.x < local.x : screen.x > local.x
            }
            .min { lhs, rhs in
                distanceScore(from: local, to: lhs) < distanceScore(from: local, to: rhs)
            }
    }

    private func distanceScore(from source: PeerScreen, to target: PeerScreen) -> Double {
        abs(target.x - source.x) + abs(target.y - source.y) * 0.6
    }
}

enum ScreenLayoutStore {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/siu", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    static func load() -> ScreenLayout {
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-arrow/layout.json")
        let sourceURL = FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : legacyURL
        guard let data = try? Data(contentsOf: sourceURL),
              let layout = try? JSONDecoder().decode(ScreenLayout.self, from: data) else {
            return .initial
        }
        return layout
    }

    static func save(_ layout: ScreenLayout) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: fileURL, options: .atomic)
    }
}
