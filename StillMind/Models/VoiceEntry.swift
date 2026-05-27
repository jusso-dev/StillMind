import Foundation

/// Core data model representing a single voice journal entry.
struct VoiceEntry: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    let encryptedAudioFilename: String
    var transcript: String
    var summaryTitle: String
    var summaryText: String
    var tags: [String]
    var actionItems: [String]
    var peopleMentioned: [String]
    var mood: String?
    /// Encryption key version used to encrypt this entry's audio
    var keyVersion: Int
    /// Optional project this entry belongs to
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        durationSeconds: Double,
        encryptedAudioFilename: String,
        transcript: String = "",
        summaryTitle: String = "",
        summaryText: String = "",
        tags: [String] = [],
        actionItems: [String] = [],
        peopleMentioned: [String] = [],
        mood: String? = nil,
        keyVersion: Int = 1,
        projectId: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.encryptedAudioFilename = encryptedAudioFilename
        self.transcript = transcript
        self.summaryTitle = summaryTitle
        self.summaryText = summaryText
        self.tags = tags
        self.actionItems = actionItems
        self.peopleMentioned = peopleMentioned
        self.mood = mood
        self.keyVersion = keyVersion
        self.projectId = projectId
    }
}
