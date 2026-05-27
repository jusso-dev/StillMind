import SwiftUI

/// Displays all projects as folders for grouping journal entries.
struct ProjectListView: View {
    let viewModel: ProjectListViewModel
    let secureFileStore: SecureFileStore
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository

    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectDescription = ""
    @State private var searchText = ""

    private var filteredProjects: [Project] {
        if searchText.isEmpty { return viewModel.projects }
        let lowered = searchText.lowercased()
        return viewModel.projects.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.description.lowercased().contains(lowered)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading projects...")
                } else if viewModel.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a project to organize your journal entries.")
                    )
                } else {
                    List {
                        ForEach(filteredProjects) { project in
                            NavigationLink {
                                ProjectDetailView(
                                    project: project,
                                    viewModel: viewModel,
                                    secureFileStore: secureFileStore,
                                    entryRepository: entryRepository,
                                    projectRepository: projectRepository
                                )
                            } label: {
                                ProjectRowView(project: project, viewModel: viewModel)
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let project = filteredProjects[index]
                                    await viewModel.deleteProject(project)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .searchable(text: $searchText, prompt: "Search projects...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewProject = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .alert("New Project", isPresented: $showingNewProject) {
                TextField("Project name", text: $newProjectName)
                TextField("Description (optional)", text: $newProjectDescription)
                Button("Cancel", role: .cancel) {
                    newProjectName = ""
                    newProjectDescription = ""
                }
                Button("Create") {
                    let name = newProjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await viewModel.createProject(name: name, description: newProjectDescription)
                        newProjectName = ""
                        newProjectDescription = ""
                    }
                }
            }
            .task {
                await viewModel.loadProjects()
            }
            .refreshable {
                await viewModel.loadProjects()
            }
        }
    }
}

// MARK: - Project Row

struct ProjectRowView: View {
    let project: Project
    let viewModel: ProjectListViewModel

    @State private var entryCount: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)

                if !project.description.isEmpty {
                    Text(project.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text(viewModel.formattedDate(project.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(entryCount) entries")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            entryCount = await viewModel.entryCount(for: project)
        }
    }
}
