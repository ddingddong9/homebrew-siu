import Foundation

struct ArrowMessage: Codable, Equatable {
    static let protocolVersion = 1

    let version: Int
    let id: UUID
    let normalizedY: Double
    let sentAt: Date

    init(normalizedY: Double) {
        self.version = Self.protocolVersion
        self.id = UUID()
        self.normalizedY = min(max(normalizedY, 0.08), 0.92)
        self.sentAt = Date()
    }
}
