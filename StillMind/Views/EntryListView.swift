import SwiftUI

/// Unified Journal view with entries, projects, and search.
struct EntryListView: View {
    enum JournalTab: String, CaseIterable {
        case entries = "Entries"
        case projects = "Projects"
    }

    let viewModel: EntryListViewModel
    let projectViewModel: ProjectListViewModel
    let secureFileStore: SecureFileStore
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository

    @State private var selectedTab: JournalTab = .entries
    @State private var searchText = ""
    @State private var entryToDelete: VoiceEntry?
    @State private var showingDeleteConfirmation = false
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectDescription = ""

    // MARK: - Filtered Data

    private var filteredEntries: [VoiceEntry] {
        if searchText.isEmpty { return viewModel.entries }
        let lowered = searchText.lowercased()
        return viewModel.entries.filter {
            $0.summaryTitle.lowercased().contains(lowered) ||
            $0.transcript.lowercased().contains(lowered) ||
            $0.tags.contains(where: { $0.lowercased().contains(lowered) })
        }
    }

    private var filteredProjects: [Project] {
        if searchText.isEmpty { return projectViewModel.projects }
        let lowered = searchText.lowercased()
        return projectViewModel.projects.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.description.lowercased().contains(lowered)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(JournalTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch selectedTab {
                case .entries:
                    entriesContent
                case .projects:
                    projectsContent
                }
            }
            .navigationTitle("Journal")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search entries & projects...")
            .toolbar {
                if selectedTab == .projects {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Project", systemImage: "folder.badge.plus") {
                            showingNewProject = true
                        }
                    }
                }
            }
            .task {
                await viewModel.loadEntries()
                await projectViewModel.loadProjects()
            }
            .refreshable {
                await viewModel.loadEntries()
                await projectViewModel.loadProjects()
            }
            .alert("Delete Entry?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    entryToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        Task { await viewModel.deleteEntry(entry) }
                    }
                    entryToDelete = nil
                }
            } message: {
                if let entry = entryToDelete {
                    Text("Are you sure you want to delete \"\(entry.summaryTitle.isEmpty ? "Untitled Entry" : entry.summaryTitle)\"? This cannot be undone.")
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
                        await projectViewModel.createProject(name: name, description: newProjectDescription)
                        newProjectName = ""
                        newProjectDescription = ""
                    }
                }
            }
        }
    }

    // MARK: - Entries Content

    @ViewBuilder
    private var entriesContent: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView("Loading entries...")
            Spacer()
        } else if filteredEntries.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "No Entries Yet",
                    systemImage: "mic.badge.plus",
                    description: Text("Record your first voice journal entry to get started.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            List {
                ForEach(filteredEntries) { entry in
                    NavigationLink {
                        EntryDetailView(
                            entry: entry,
                            secureFileStore: secureFileStore,
                            entryRepository: entryRepository,
                            projectRepository: projectRepository
                        )
                    } label: {
                        EntryRowView(entry: entry, viewModel: viewModel)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            entryToDelete = entry
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Projects Content

    @ViewBuilder
    private var projectsContent: some View {
        if projectViewModel.isLoading {
            Spacer()
            ProgressView("Loading projects...")
            Spacer()
        } else if filteredProjects.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a project to organize your journal entries.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            List {
                ForEach(filteredProjects) { project in
                    NavigationLink {
                        ProjectDetailView(
                            project: project,
                            viewModel: projectViewModel,
                            secureFileStore: secureFileStore,
                            entryRepository: entryRepository,
                            projectRepository: projectRepository
                        )
                    } label: {
                        ProjectRowView(project: project, viewModel: projectViewModel)
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            let project = filteredProjects[index]
                            await projectViewModel.deleteProject(project)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Entry Row

struct EntryRowView: View {
    let entry: VoiceEntry
    let viewModel: EntryListViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title + duration
            HStack(alignment: .firstTextBaseline) {
                Text(entry.summaryTitle.isEmpty ? "Untitled Entry" : entry.summaryTitle)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                Spacer()
                Text(formatDuration(entry.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // Transcript preview
            if !entry.transcript.isEmpty {
                Text(entry.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Metadata: date + mood
            HStack(spacing: Spacing.sm) {
                Text(entry.createdAt.relativeShort)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let mood = entry.mood {
                    MoodPill(mood: mood)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
