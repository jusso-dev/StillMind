import SwiftUI

/// Displays entries within a specific project.
struct ProjectDetailView: View {
    let project: Project
    let viewModel: ProjectListViewModel
    let secureFileStore: SecureFileStore
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository

    @State private var entries: [VoiceEntry] = []
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedDescription: String = ""

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "doc.text",
                    description: Text("Record an entry and assign it to this project.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink {
                            EntryDetailView(
                                entry: entry,
                                secureFileStore: secureFileStore,
                                entryRepository: entryRepository,
                                projectRepository: projectRepository
                            )
                        } label: {
                            ProjectEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Project", systemImage: "pencil") {
                    editedName = project.name
                    editedDescription = project.description
                    isEditing = true
                }
            }
        }
        .alert("Edit Project", isPresented: $isEditing) {
            TextField("Name", text: $editedName)
            TextField("Description", text: $editedDescription)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = editedName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                var updated = project
                updated.name = name
                updated.description = editedDescription
                Task { await viewModel.updateProject(updated) }
            }
        }
        .task {
            entries = await viewModel.entries(for: project)
        }
        .refreshable {
            entries = await viewModel.entries(for: project)
        }
    }
}

struct ProjectEntryRow: View {
    let entry: VoiceEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.summaryTitle.isEmpty ? "Untitled Entry" : entry.summaryTitle)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

            Text(entry.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
