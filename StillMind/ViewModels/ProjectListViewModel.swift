import Foundation
import Observation

/// ViewModel for the projects list and detail screens.
@Observable
@MainActor
final class ProjectListViewModel {
    var projects: [Project] = []
    var isLoading = false
    var errorMessage: String?

    private let projectRepository: ProjectRepository
    private let entryRepository: EntryRepository

    nonisolated private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    init(projectRepository: ProjectRepository, entryRepository: EntryRepository) {
        self.projectRepository = projectRepository
        self.entryRepository = entryRepository
    }

    func loadProjects() async {
        isLoading = true
        do {
            projects = try await projectRepository.allProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createProject(name: String, description: String = "") async {
        let project = Project(name: name, description: description)
        do {
            try await projectRepository.save(project)
            projects.insert(project, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProject(_ project: Project) async {
        do {
            try await projectRepository.update(project)
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            try await projectRepository.delete(id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns all entries belonging to a specific project.
    func entries(for project: Project) async -> [VoiceEntry] {
        do {
            let all = try await entryRepository.allEntries()
            return all.filter { $0.projectId == project.id }
        } catch {
            return []
        }
    }

    /// Returns the entry count for a project.
    func entryCount(for project: Project) async -> Int {
        await entries(for: project).count
    }

    func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}
