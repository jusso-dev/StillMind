import Foundation

/// Detects crisis-related language in journal text and provides support resources.
///
/// This is a keyword-based check that runs on-device. It does **not** block or
/// censor the user's entry — it simply flags when the content suggests the user
/// may benefit from speaking to a crisis support service.
struct SafetyService: Sendable {

    /// Returns `true` when the text contains language that suggests
    /// the user may be in crisis or experiencing thoughts of self-harm.
    func detectsCrisisLanguage(in text: String) -> Bool {
        let lowered = text.lowercased()

        // Exact-phrase matching (order matters — check phrases before single words
        // to avoid false positives on common words like "end" or "hurt").
        let phrases: [String] = [
            "kill myself",
            "end my life",
            "want to die",
            "wish i was dead",
            "wish i were dead",
            "better off dead",
            "don't want to live",
            "dont want to live",
            "don't want to be here",
            "dont want to be here",
            "can't go on",
            "cant go on",
            "no reason to live",
            "not worth living",
            "take my own life",
            "end it all",
            "hurt myself",
            "harm myself",
            "self harm",
            "self-harm",
            "suicidal",
            "suicide",
        ]

        for phrase in phrases {
            if lowered.contains(phrase) {
                return true
            }
        }

        return false
    }

    /// Lifeline Australia phone number.
    static let lifelineNumber = "13 11 14"

    /// A short, compassionate message shown when crisis language is detected.
    static let supportMessage = """
        It sounds like you might be going through a really tough time. \
        You don't have to face this alone — trained counsellors are available \
        24 hours a day, 7 days a week.
        """
}
