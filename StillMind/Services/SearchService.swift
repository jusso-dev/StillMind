import Foundation

/// Provides full-text search across journal entries and projects.
final class SearchService: @unchecked Sendable {
    private let repository: EntryRepository
    private let projectRepository: ProjectRepository

    init(repository: EntryRepository, projectRepository: ProjectRepository) {
        self.repository = repository
        self.projectRepository = projectRepository
    }

    /// Full-text search across transcripts, summaries, and tags.
    func search(query: String) async throws -> [VoiceEntry] {
        try await repository.search(query: query)
    }

    /// Filter entries by a specific tag.
    func filterByTag(_ tag: String) async throws -> [VoiceEntry] {
        try await repository.searchByTag(tag)
    }

    /// Filter entries within a date range.
    func filterByDateRange(from: Date, to: Date) async throws -> [VoiceEntry] {
        try await repository.searchByDateRange(from: from, to: to)
    }

    /// Returns all unique tags across all entries.
    func allTags() async throws -> [String] {
        let entries = try await repository.allEntries()
        let tagSet = Set(entries.flatMap { $0.tags })
        return tagSet.sorted()
    }

    /// Searches projects by name or description.
    func searchProjects(query: String) async throws -> [Project] {
        try await projectRepository.search(query: query)
    }

    /// Returns all projects.
    func allProjects() async throws -> [Project] {
        try await projectRepository.allProjects()
    }

    /// Returns entries belonging to a specific project.
    func entries(forProject projectId: UUID) async throws -> [VoiceEntry] {
        let all = try await repository.allEntries()
        return all.filter { $0.projectId == projectId }
    }
}
