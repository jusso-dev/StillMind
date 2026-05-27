import Foundation

/// Generates structured summaries from transcripts using extractive summarization.
///
/// Uses ExtractiveSummarizer to pick the most representative sentences,
/// combined with Core ML tag/mood hints.
final class SummarizationService: @unchecked Sendable {

    private let summarizer = ExtractiveSummarizer()

    /// Summarizes a transcript using extractive summarization and Core ML hints.
    ///
    /// - Parameters:
    ///   - transcript: Raw journal text.
    ///   - detectedTags: Tags from the Core ML tagger.
    ///   - detectedMoods: Moods from the Core ML tagger.
    func summarize(
        transcript: String,
        detectedTags: [String] = [],
        detectedMoods: [String] = []
    ) async throws -> StructuredSummary {
        let shortSummary = summarizer.summarize(
            text: transcript,
            contextTags: detectedTags,
            contextMoods: detectedMoods,
            maxSentences: 2
        )

        let titleWords = shortSummary
            .split { $0.isWhitespace }
            .prefix(10)
            .joined(separator: " ")
        let title = titleWords.isEmpty ? "Voice Entry" : titleWords

        return StructuredSummary(
            title: title,
            shortSummary: shortSummary,
            tags: detectedTags,
            actionItems: [],
            peopleMentioned: [],
            mood: detectedMoods.first
        )
    }
}

enum SummarizationError: LocalizedError {
    case invalidResponse
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Failed to parse summary"
        case .modelUnavailable: return "Summarization is not available"
        }
    }
}
