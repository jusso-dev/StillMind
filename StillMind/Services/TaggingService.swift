import Foundation
import NaturalLanguage

/// Classifies journal text into topic tags and mood labels using the
/// on-device Core ML StillMindTagger model, with layered fallbacks so
/// every entry always receives a mood label.
final class TaggingService: @unchecked Sendable {

    private var tagger: StillMindTagger?

    init() {
        tagger = try? StillMindTagger()
    }

    /// Predicts tags and moods for the given transcript.
    ///
    /// Fallback chain (every entry gets a mood):
    ///   1. Core ML labels above the model's 0.5 confidence threshold
    ///   2. Top Core ML mood if probability ≥ 0.15 (handles short text)
    ///   3. Keyword match against common mood words
    ///   4. Apple NaturalLanguage sentiment score mapped to a mood label
    func classify(transcript: String) -> (tags: [String], moods: [String]) {
        let modelResult = tagger.flatMap { try? $0.predict(text: transcript) }

        var moods = modelResult?.moods ?? []
        let tags = modelResult?.tags ?? []

        // 2. Soft threshold on model's own probabilities
        if moods.isEmpty, let probs = modelResult?.moodProbabilities,
           let top = probs.max(by: { $0.value < $1.value }), top.value >= 0.15 {
            moods = [top.key]
        }

        // 3. Keyword match
        if moods.isEmpty, let keywordHit = keywordMood(from: transcript) {
            moods = [keywordHit]
        }

        // 4. Sentiment fallback — always produces a label for any English text
        if moods.isEmpty {
            moods = [sentimentMood(from: transcript)]
        }

        return (tags, moods)
    }

    /// Keyword matcher for common mood phrases.
    private func keywordMood(from text: String) -> String? {
        let lowered = text.lowercased()
        let keywords: [(mood: String, words: [String])] = [
            ("grateful",    ["grateful", "thankful", "appreciate", "blessed", "lucky"]),
            ("positive",    ["happy", "great", "wonderful", "excited", "joy", "amazing", "fantastic", "love"]),
            ("calm",        ["calm", "peaceful", "relaxed", "serene", "quiet"]),
            ("hopeful",     ["hopeful", "optimistic", "looking forward"]),
            ("determined",  ["determined", "motivated", "committed", "focused"]),
            ("content",     ["content", "satisfied", "comfortable", "fine", "alright", "nice"]),
            ("reflective",  ["reflect", "thinking", "wonder", "realize", "wondering"]),
            ("overwhelmed", ["overwhelmed", "too much", "swamped", "drowning"]),
            ("stressed",    ["stress", "stressed", "pressure", "tense"]),
            ("anxious",     ["anxious", "anxiety", "worry", "worried", "nervous"]),
            ("frustrated",  ["frustrated", "stuck", "annoyed", "struggling"]),
            ("angry",       ["angry", "anger", "mad", "furious", "pissed"]),
            ("fearful",     ["afraid", "fear", "scared", "terrified"]),
            ("sad",         ["sad", "unhappy", "down", "depressed", "upset", "lonely"]),
            ("numb",        ["numb", "empty", "hollow", "detached"]),
        ]
        for entry in keywords {
            if entry.words.contains(where: { lowered.contains($0) }) {
                return entry.mood
            }
        }
        return nil
    }

    /// Apple's built-in sentiment analyzer as a universal fallback.
    /// Always returns a valid mood label.
    private func sentimentMood(from text: String) -> String {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (sentiment, _) = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )
        let score = Double(sentiment?.rawValue ?? "0") ?? 0

        switch score {
        case 0.5...1.0:    return "positive"
        case 0.15..<0.5:   return "content"
        case -0.15..<0.15: return "reflective"
        case -0.5..<(-0.15): return "sad"
        default:           return "overwhelmed"
        }
    }
}
