import Foundation
import NaturalLanguage

/// Pure-Swift extractive summariser using NLTokenizer.
///
/// Splits a journal transcript into sentences, scores each by keyword
/// overlap with detected tags/moods, sentence position, and length,
/// then returns the top 2–3 sentences in their original order.
final class ExtractiveSummarizer {

    // MARK: - Tag keyword vocabulary

    private static let tagKeywords: [String: [String]] = [
        "family": [
            "family", "mom", "dad", "parent", "parents", "brother", "sister", "sibling",
            "kid", "kids", "child", "children", "son", "daughter", "grandma", "grandpa",
            "grandmother", "grandfather", "aunt", "uncle", "cousin", "spouse", "husband", "wife",
        ],
        "work": [
            "work", "job", "boss", "colleague", "meeting", "project", "deadline", "office",
            "career", "manager", "coworker", "employee", "task", "assignment", "client", "business",
        ],
        "health": [
            "health", "sick", "ill", "doctor", "hospital", "exercise", "workout", "diet",
            "sleep", "medication", "pain", "symptom", "therapy", "wellness", "tired", "exhausted",
        ],
        "relationships": [
            "relationship", "friend", "friends", "partner", "date", "dating", "love",
            "romantic", "connection", "trust", "communication", "communicate",
        ],
        "finances": [
            "money", "finance", "finances", "bill", "bills", "debt", "budget", "saving",
            "savings", "expense", "expenses", "income", "salary", "loan", "mortgage", "rent",
        ],
        "memories": [
            "remember", "memory", "memories", "past", "childhood", "nostalgia", "nostalgic",
            "miss", "missing", "years ago", "back then",
        ],
        "grief": [
            "grief", "loss", "lost", "died", "death", "mourning", "grieve", "passing", "funeral",
        ],
        "goals": [
            "goal", "goals", "plan", "plans", "dream", "dreams", "future", "achieve",
            "ambition", "aspiration", "target", "milestone",
        ],
        "gratitude": [
            "grateful", "thankful", "appreciate", "appreciation", "blessed", "lucky",
            "fortunate", "gratitude", "thanks",
        ],
        "conflict": [
            "argument", "fight", "conflict", "disagree", "disagreement", "tension",
            "dispute", "argue", "confrontation",
        ],
        "self_image": [
            "confidence", "self-esteem", "identity", "worth", "value", "believe", "proud",
            "shame", "insecure", "self-worth",
        ],
        "parenting": [
            "parenting", "toddler", "teen", "teenager", "school", "homework", "bedtime",
        ],
        "creativity": [
            "creative", "creativity", "art", "writing", "music", "draw", "paint", "design",
            "create", "craft",
        ],
        "spirituality": [
            "spiritual", "spirituality", "faith", "prayer", "pray", "meditation", "meditate",
            "mindfulness", "soul", "purpose", "meaning",
        ],
        "loneliness": [
            "lonely", "alone", "isolated", "isolation", "disconnected", "longing",
        ],
    ]

    // MARK: - Mood keyword vocabulary

    private static let moodKeywords: [String: [String]] = [
        "stressed": ["stress", "stressed", "pressure", "tense", "tension"],
        "anxious": ["anxious", "anxiety", "worry", "worried", "nervous", "dread", "uneasy"],
        "positive": ["happy", "good", "great", "wonderful", "excited", "joy", "joyful", "thrilled"],
        "reflective": ["reflect", "thinking", "wonder", "realize", "realization", "insight", "contemplate"],
        "sad": ["sad", "unhappy", "down", "depressed", "upset", "cry", "crying", "tears", "heartbroken"],
        "angry": ["angry", "anger", "mad", "furious", "irritated", "annoy", "rage"],
        "calm": ["calm", "peaceful", "relaxed", "serene", "quiet", "tranquil"],
        "hopeful": ["hope", "hopeful", "optimistic", "look forward", "improve"],
        "overwhelmed": ["overwhelmed", "too much", "drown", "swamped"],
        "numb": ["numb", "empty", "hollow", "blank", "detached"],
        "grateful": ["grateful", "thankful", "appreciate", "blessed", "fortunate"],
        "frustrated": ["frustrated", "stuck", "struggle"],
        "content": ["content", "satisfied", "comfortable", "at peace"],
        "fearful": ["afraid", "fear", "scared", "terrified", "frightened"],
        "determined": ["determined", "motivated", "committed", "resolve", "persist"],
    ]

    // MARK: - Public API

    /// Extracts top 2–3 representative sentences from `text`.
    ///
    /// - Parameters:
    ///   - text: The full journal transcript.
    ///   - contextTags: Tag labels already detected (improves scoring accuracy).
    ///   - contextMoods: Mood labels already detected.
    ///   - maxSentences: Maximum number of sentences to return (default 2).
    /// - Returns: Selected sentences joined by a space, in original document order.
    func summarize(
        text: String,
        contextTags: [String] = [],
        contextMoods: [String] = [],
        maxSentences: Int = 2
    ) -> String {
        let sentences = tokenizeSentences(text)
        guard !sentences.isEmpty else { return text }
        if sentences.count == 1 { return sentences[0].text }

        let keywords = buildKeywordSet(tags: contextTags, moods: contextMoods, rawText: text)
        let scored = score(sentences: sentences, keywords: keywords)

        let topN = min(maxSentences, sentences.count)
        let topIndices = Set(scored.prefix(topN).map { $0.index })

        return sentences
            .filter { topIndices.contains($0.index) }
            .map { $0.text }
            .joined(separator: " ")
    }

    // MARK: - Sentence tokenization

    private struct SentenceInfo {
        let index: Int
        let text: String
        let wordCount: Int
    }

    private func tokenizeSentences(_ text: String) -> [SentenceInfo] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [SentenceInfo] = []
        var rawIndex = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = sentence.split { $0.isWhitespace }.count
            // Filter out very short fragments (fewer than 5 words)
            if wordCount >= 5 {
                sentences.append(SentenceInfo(index: rawIndex, text: sentence, wordCount: wordCount))
            }
            rawIndex += 1
            return true
        }
        return sentences
    }

    // MARK: - Keyword set construction

    private func buildKeywordSet(tags: [String], moods: [String], rawText: String) -> Set<String> {
        var keywords = Set<String>()

        for tag in tags {
            if let words = Self.tagKeywords[tag] { keywords.formUnion(words) }
        }
        for mood in moods {
            if let words = Self.moodKeywords[mood] { keywords.formUnion(words) }
        }

        // If no context provided, infer from raw text by scanning all vocab
        if tags.isEmpty && moods.isEmpty {
            let lowered = rawText.lowercased()
            for (_, words) in Self.tagKeywords {
                for word in words where lowered.contains(word) { keywords.insert(word) }
            }
            for (_, words) in Self.moodKeywords {
                for word in words where lowered.contains(word) { keywords.insert(word) }
            }
        }

        return keywords
    }

    // MARK: - Scoring

    private struct ScoredSentence {
        let index: Int
        let score: Double
    }

    private func score(sentences: [SentenceInfo], keywords: Set<String>) -> [ScoredSentence] {
        let n = sentences.count

        return sentences.enumerated().map { i, info in
            var s = 0.0
            let lowered = info.text.lowercased()

            // Keyword overlap — each matching keyword adds weight
            let matchCount = keywords.filter { lowered.contains($0) }.count
            s += Double(matchCount) * 1.5

            // Length bonus: prefer medium-length sentences (10–40 words)
            if info.wordCount >= 10 && info.wordCount <= 40 {
                s += 1.0
            }

            // Position bonus
            if i == 0       { s += 2.0 }   // first sentence
            if i == n - 1   { s += 1.5 }   // last sentence
            if i == 1 && n > 3 { s += 0.5 } // second sentence mild boost

            return ScoredSentence(index: info.index, score: s)
        }
        .sorted { $0.score > $1.score }
    }
}
