import SwiftUI

/// Calm home screen — the emotional anchor of the app.
struct HomeView: View {
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository
    let secureFileStore: SecureFileStore
    @Bindable var recordViewModel: RecordViewModel

    @State private var recentEntries: [VoiceEntry] = []
    @State private var showingRecorder = false
    @State private var entryToDelete: VoiceEntry?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good evening"
        }
    }

    private var todayEntries: [VoiceEntry] {
        recentEntries.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var olderEntries: [VoiceEntry] {
        Array(recentEntries.filter { !Calendar.current.isDateInToday($0.createdAt) }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Greeting
                    greetingSection

                    // Record CTA
                    recordCard
                        .padding(.horizontal, Spacing.md)

                    // Journaling activity card
                    if recentEntries.count >= 3 {
                        NavigationLink {
                            InsightsView(entryRepository: entryRepository, projectRepository: projectRepository)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack {
                                    Text("Last 2 weeks")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("See all")
                                        .font(.caption)
                                        .foregroundStyle(Color.smAccent)
                                }

                                PresenceStrip(entries: recentEntries)

                                // Explain what the dots mean
                                HStack(spacing: Spacing.lg) {
                                    HStack(spacing: Spacing.xs) {
                                        Circle()
                                            .fill(Color.smAccent.opacity(0.55))
                                            .frame(width: 8, height: 8)
                                        Text("Journaled")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    HStack(spacing: Spacing.xs) {
                                        Circle()
                                            .fill(Color(.quaternarySystemFill))
                                            .frame(width: 8, height: 8)
                                        Text("No entry")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                // Summary text
                                let journaledDays = recentEntries.filter {
                                    $0.createdAt > Calendar.current.date(byAdding: .day, value: -14, to: Date())!
                                }.count
                                Text("\(journaledDays) reflections in the last 14 days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.md)
                    }

                    // Today's entries
                    if !todayEntries.isEmpty {
                        entriesSection(title: "Today", entries: todayEntries)
                    }

                    // Recent entries
                    if !olderEntries.isEmpty {
                        entriesSection(title: "Recent", entries: olderEntries)
                    }

                    // Empty state
                    if recentEntries.isEmpty {
                        emptyState
                            .padding(.horizontal, Spacing.md)
                    }

                    Spacer(minLength: Spacing.xxl)
                }
                .padding(.top, Spacing.sm)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("StillMind")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.smAccent)
                }
            }
            .task {
                await loadEntries()
                await recordViewModel.refreshEntryCount()
            }
            .refreshable {
                await loadEntries()
            }
            .fullScreenCover(isPresented: $showingRecorder, onDismiss: {
                Task { await loadEntries() }
            }) {
                RecordView(viewModel: recordViewModel, isPresented: $showingRecorder)
            }
            .confirmationDialog(
                "Delete Entry",
                isPresented: Binding(
                    get: { entryToDelete != nil },
                    set: { if !$0 { entryToDelete = nil } }
                ),
                presenting: entryToDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    deleteEntry(entry)
                }
            } message: { entry in
                Text("Delete \"\(entry.summaryTitle.isEmpty ? "Untitled Entry" : entry.summaryTitle)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(greeting)
                .font(.largeTitle.weight(.semibold))

            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Record Card

    private var recordCard: some View {
        Button {
            Haptics.medium()
            showingRecorder = true
        } label: {
            VStack(spacing: Spacing.md) {
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.smAccent)
                    .padding(.bottom, Spacing.xs)

                Text("Record your thoughts")
                    .font(.headline)

                Text("Speak freely — everything stays on your device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record a new voice journal entry")
    }

    // MARK: - Entry Sections

    private func entriesSection(title: String, entries: [VoiceEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.md)

            ForEach(entries) { entry in
                SwipeToDeleteCard {
                    NavigationLink {
                        EntryDetailView(
                            entry: entry,
                            secureFileStore: secureFileStore,
                            entryRepository: entryRepository,
                            projectRepository: projectRepository
                        )
                    } label: {
                        HomeEntryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                } onDelete: {
                    entryToDelete = entry
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "leaf")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.smAccent.opacity(0.6))

            Text("Your journal is empty")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Record your first entry to begin your reflection practice.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    // MARK: - Data

    private func loadEntries() async {
        recentEntries = (try? await entryRepository.allEntries()) ?? []
    }

    private func deleteEntry(_ entry: VoiceEntry) {
        Task {
            try? await entryRepository.delete(id: entry.id)
            withAnimation {
                recentEntries.removeAll { $0.id == entry.id }
            }
        }
    }
}

// MARK: - Swipe to Delete Card

/// Wraps content with a left-swipe gesture that reveals a delete button.
private struct SwipeToDeleteCard<Content: View>: View {
    @ViewBuilder let content: Content
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    private let deleteWidth: CGFloat = 80
    private let triggerThreshold: CGFloat = -120

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button revealed behind the card
            Button(role: .destructive) {
                onDelete()
                withAnimation(.spring(response: 0.3)) { offset = 0 }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .clipShape(.rect(cornerRadius: 16))
            }
            .opacity(offset < 0 ? 1 : 0)

            // Card content
            content
                .accessibilityAction(named: "Delete", onDelete)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only allow left swipe
                            let translation = value.translation.width
                            if translation < 0 {
                                offset = translation
                            } else if offset < 0 {
                                // Allow dragging back to the right
                                offset = min(0, offset + translation)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3)) {
                                if value.translation.width < triggerThreshold {
                                    // Snapped open — user can tap delete
                                    offset = -deleteWidth
                                } else {
                                    offset = 0
                                }
                            }
                        }
                )
        }
    }
}

// MARK: - Home Entry Card

struct HomeEntryCard: View {
    let entry: VoiceEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title
            Text(entry.summaryTitle.isEmpty ? "Untitled Entry" : entry.summaryTitle)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .foregroundStyle(.primary)

            // Transcript preview
            if !entry.transcript.isEmpty {
                Text(entry.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Metadata row
            HStack(spacing: Spacing.sm) {
                if let mood = entry.mood {
                    MoodPill(mood: mood)
                }

                Text(formatDuration(entry.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(entry.createdAt.relativeShort)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
