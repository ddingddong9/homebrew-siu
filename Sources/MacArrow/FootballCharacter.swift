import AppKit

enum FootballTeam: Int, Codable, CaseIterable {
    case ronaldo = 0, messi = 1
    var title: String { self == .ronaldo ? "호날두팀" : "메시팀" }
    var opposite: FootballTeam { self == .ronaldo ? .messi : .ronaldo }
}

@MainActor
final class MessiSprites {
    static let shared = MessiSprites()
    private let clips: [String:[NSImage]]
    private init() {
        clips = Dictionary(uniqueKeysWithValues: [("idle",1),("shot",23),("tackle",20),("phantom",7)].map { name,count in
            (name,(1...count).compactMap { ResourceBundle.images.url(forResource:String(format:"messi-%@-%02d",name,$0),withExtension:"png").flatMap(NSImage.init(contentsOf:)) })
        })
    }
    func image(_ clip: String = "idle", progress: Double = 0) -> NSImage? {
        guard let frames = clips[clip], !frames.isEmpty else { return clips["idle"]?.first }
        return frames[min(frames.count-1,max(0,Int(min(1,max(0,progress))*Double(frames.count-1))))]
    }
}
