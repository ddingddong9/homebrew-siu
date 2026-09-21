import Foundation

struct ArrowMessage: Codable, Equatable {
    static let protocolVersion = 1

    let version: Int
    let id: UUID
    let normalizedY: Double
    let sentAt: Date
    let entryEdge: String?

    init(normalizedY: Double, entryEdge: String = "right") {
        self.version = Self.protocolVersion
        self.id = UUID()
        self.normalizedY = min(max(normalizedY, 0.08), 0.92)
        self.sentAt = Date()
        self.entryEdge = entryEdge
    }
}
