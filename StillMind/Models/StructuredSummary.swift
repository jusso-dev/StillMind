import Foundation

/// Structured output from the on-device LLM summarization.
struct StructuredSummary: Codable {
    let title: String
    let shortSummary: String
    let tags: [String]
    let actionItems: [String]
    let peopleMentioned: [String]
    let mood: String?
}
