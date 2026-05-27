import Foundation

/// Persists projects using JSON file storage.
actor ProjectRepository {
    private let storageURL: URL
    private var projects: [Project] = []
    private var loaded = false

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("projects.json")
    }

    // MARK: - CRUD

    func loadProjects() throws -> [Project] {
        if loaded { return projects }

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            loaded = true
            return []
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        projects = try decoder.decode([Project].self, from: data)
        projects.sort { $0.createdAt > $1.createdAt }
        loaded = true
        return projects
    }

    func save(_ project: Project) throws {
        if !loaded { _ = try loadProjects() }
        projects.insert(project, at: 0)
        try persist()
    }

    func update(_ project: Project) throws {
        if !loaded { _ = try loadProjects() }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        try persist()
    }

    func delete(id: UUID) throws {
        if !loaded { _ = try loadProjects() }
        projects.removeAll { $0.id == id }
        try persist()
    }

    func allProjects() throws -> [Project] {
        try loadProjects()
    }

    func project(byId id: UUID) throws -> Project? {
        let all = try loadProjects()
        return all.first { $0.id == id }
    }

    // MARK: - Search

    func search(query: String) throws -> [Project] {
        let all = try loadProjects()
        let lowered = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.description.lowercased().contains(lowered)
        }
    }

    /// Deletes all projects from disk and clears the in-memory cache.
    func deleteAll() throws {
        projects = []
        loaded = true
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Private

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(projects)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
    }
}
