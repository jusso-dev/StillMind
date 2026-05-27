import Foundation

/// A project groups related journal entries together for organization.
struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
    }
}
