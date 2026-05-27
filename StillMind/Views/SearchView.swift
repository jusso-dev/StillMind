import SwiftUI

/// Search screen for finding entries by text, tag, or date.
struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let secureFileStore: SecureFileStore
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tag filter chips
                if !viewModel.allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.allTags, id: \.self) { tag in
                                Button {
                                    Task { await viewModel.filterByTag(tag) }
                                } label: {
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            viewModel.selectedTag == tag
                                                ? Color.accentColor.opacity(0.2)
                                                : Color.secondary.opacity(0.1)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                // Results
                if viewModel.isSearching {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.results.isEmpty && !viewModel.query.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView(
                        "Search Your Journal",
                        systemImage: "magnifyingglass",
                        description: Text("Search across transcripts, summaries, and tags.")
                    )
                } else {
                    List {
                        // Project results
                        if !viewModel.projectResults.isEmpty {
                            Section("Projects") {
                                ForEach(viewModel.projectResults) { project in
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading) {
                                            Text(project.name)
                                                .font(.headline)
                                            if !project.description.isEmpty {
                                                Text(project.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Entry results
                        if !viewModel.results.isEmpty {
                            Section("Entries") {
                                ForEach(viewModel.results) { entry in
                                    NavigationLink {
                                        EntryDetailView(
                                            entry: entry,
                                            secureFileStore: secureFileStore,
                                            entryRepository: entryRepository,
                                            projectRepository: projectRepository
                                        )
                                    } label: {
                                        SearchResultRow(entry: entry)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Search entries...")
            .onSubmit(of: .search) {
                Task { await viewModel.performSearch() }
            }
            .task {
                await viewModel.loadTags()
            }
        }
    }
}

struct SearchResultRow: View {
    let entry: VoiceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.summaryTitle.isEmpty ? "Untitled" : entry.summaryTitle)
                .font(.headline)
                .lineLimit(1)

            // Show transcript preview (the raw words)
            Text(entry.transcript)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text(entry.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !entry.tags.isEmpty {
                    Text(entry.tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
