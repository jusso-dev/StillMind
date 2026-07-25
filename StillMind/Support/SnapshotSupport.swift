import Foundation

/// Enables deterministic, local-only content for App Store screenshot UI tests.
///
/// This is inactive in normal launches. Fastlane passes
/// `-StillMindSnapshotMode YES` only to the screenshot test runner.
enum SnapshotMode {
    static let isActive = UserDefaults.standard.bool(forKey: "StillMindSnapshotMode")
}

/// Sample content used only while ``SnapshotMode/isActive``.
enum SnapshotSampleData {
    private static let wellbeingProjectID = uuid("A78E56EA-4164-4F92-9D90-5F289A0F1701")
    private static let workProjectID = uuid("74230603-0D6E-4E33-9D27-4AFB57C90E02")

    static let projects = [
        Project(
            id: wellbeingProjectID,
            name: "Wellbeing",
            description: "Reflections on energy, balance, and the habits that help.",
            createdAt: daysAgo(48)
        ),
        Project(
            id: workProjectID,
            name: "Creative work",
            description: "Ideas, decisions, and lessons from projects in progress.",
            createdAt: daysAgo(31)
        )
    ]

    static let entries = [
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD01"),
            createdAt: Date.now.addingTimeInterval(-5_400),
            durationSeconds: 82,
            encryptedAudioFilename: "",
            transcript: "I took a slower start this morning and noticed how much clearer everything felt. I want to protect that space before the day gets noisy.",
            summaryTitle: "A calmer start",
            summaryText: "A quiet morning created more clarity and a desire to make unhurried starts a regular habit.",
            tags: ["mindfulness", "morning", "balance"],
            actionItems: ["Leave the first 20 minutes of tomorrow unscheduled"],
            mood: "Calm",
            keyVersion: 1,
            projectId: wellbeingProjectID
        ),
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD02"),
            createdAt: daysAgo(1, hourOffset: 3),
            durationSeconds: 126,
            encryptedAudioFilename: "",
            transcript: "The product direction finally clicked today. The simplest version is also the most useful, and I can stop carrying all the extra ideas into this first release.",
            summaryTitle: "The simple path forward",
            summaryText: "Clarity arrived by choosing a focused first release and setting aside ideas that do not serve it yet.",
            tags: ["clarity", "work", "decisions"],
            actionItems: ["Write the one-page release scope", "Move later ideas into the backlog"],
            mood: "Confident",
            keyVersion: 1,
            projectId: workProjectID
        ),
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD03"),
            createdAt: daysAgo(3, hourOffset: 4),
            durationSeconds: 74,
            encryptedAudioFilename: "",
            transcript: "The walk after lunch changed the shape of the afternoon. I came back with more energy and solved the thing I had been circling all morning.",
            summaryTitle: "Movement made room",
            summaryText: "A short walk restored energy and created the mental space needed to solve a stubborn problem.",
            tags: ["energy", "movement", "focus"],
            actionItems: ["Block a short walk after lunch"],
            mood: "Happy",
            keyVersion: 1,
            projectId: wellbeingProjectID
        ),
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD04"),
            createdAt: daysAgo(5, hourOffset: 2),
            durationSeconds: 109,
            encryptedAudioFilename: "",
            transcript: "I felt stretched between too many small commitments today. None of them was difficult alone, but together they left no room to think.",
            summaryTitle: "Too many small promises",
            summaryText: "Several minor commitments combined into a stressful day with too little space for focused thought.",
            tags: ["boundaries", "stress", "time"],
            actionItems: ["Decline one nonessential commitment this week"],
            mood: "Stressed",
            keyVersion: 1,
            projectId: wellbeingProjectID
        ),
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD05"),
            createdAt: daysAgo(7, hourOffset: 5),
            durationSeconds: 95,
            encryptedAudioFilename: "",
            transcript: "The conversation was honest and kind. I had expected it to be awkward, but saying the important part plainly made us both relax.",
            summaryTitle: "Honesty felt lighter",
            summaryText: "A direct, kind conversation went better than expected and brought relief.",
            tags: ["relationships", "communication", "gratitude"],
            peopleMentioned: ["Sam"],
            mood: "Grateful",
            keyVersion: 1
        ),
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD06"),
            createdAt: daysAgo(10, hourOffset: 3),
            durationSeconds: 137,
            encryptedAudioFilename: "",
            transcript: "I keep reaching for a perfect answer before I start. The useful move is to make a small version, learn from it, and let the next step become obvious.",
            summaryTitle: "Start before certainty",
            summaryText: "Waiting for certainty is slowing progress; a small experiment will reveal the next useful step.",
            tags: ["creativity", "progress", "learning"],
            actionItems: ["Build the smallest testable version"],
            mood: "Reflective",
            keyVersion: 1,
            projectId: workProjectID
        ),
        VoiceEntry(
            id: uuid("60E45FB9-E84A-4940-9383-F67CB0C4AD07"),
            createdAt: daysAgo(13, hourOffset: 6),
            durationSeconds: 68,
            encryptedAudioFilename: "",
            transcript: "A quiet evening, dinner with people I love, and nothing urgent left to solve. I want to remember that an ordinary good day is enough.",
            summaryTitle: "An ordinary good day",
            summaryText: "A simple evening with loved ones brought contentment and appreciation for ordinary moments.",
            tags: ["gratitude", "connection", "rest"],
            peopleMentioned: ["Mia", "Tom"],
            mood: "Happy",
            keyVersion: 1
        )
    ]

    private static func daysAgo(_ days: Int, hourOffset: TimeInterval = 0) -> Date {
        Date.now.addingTimeInterval((-Double(days) * 86_400) - (hourOffset * 3_600))
    }

    private static func uuid(_ value: String) -> UUID {
        guard let identifier = UUID(uuidString: value) else {
            preconditionFailure("Invalid snapshot UUID: \(value)")
        }
        return identifier
    }
}
