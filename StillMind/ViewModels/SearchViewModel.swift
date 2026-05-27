import Foundation
import Observation

/// ViewModel for the search screen.
@Observable
@MainActor
final class SearchViewModel {
    var query: String = ""
    var results: [VoiceEntry] = []
    var projectResults: [Project] = []
    var allTags: [String] = []
    var selectedTag: String?
    var isSearching = false

    private let searchService: SearchService

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    func performSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            projectResults = []
            return
        }
        isSearching = true
        do {
            async let entrySearch = searchService.search(query: query)
            async let projectSearch = searchService.searchProjects(query: query)
            results = try await entrySearch
            projectResults = try await projectSearch
        } catch {
            results = []
            projectResults = []
        }
        isSearching = false
    }

    func filterByTag(_ tag: String) async {
        isSearching = true
        selectedTag = tag
        do {
            results = try await searchService.filterByTag(tag)
        } catch {
            results = []
        }
        isSearching = false
    }

    func loadTags() async {
        do {
            allTags = try await searchService.allTags()
        } catch {
            allTags = []
        }
    }

    func clearSearch() {
        query = ""
        results = []
        projectResults = []
        selectedTag = nil
    }
}
