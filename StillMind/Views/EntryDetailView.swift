import SwiftUI
import AVFoundation

/// Displays the full details of a single journal entry.
struct EntryDetailView: View {
    @State private var entry: VoiceEntry
    let secureFileStore: SecureFileStore
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository

    @State private var isPlayingAudio = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var tempAudioURL: URL?
    @State private var playbackError: String?
    @State private var availableProjects: [Project] = []
    @State private var showingProjectPicker = false
    @State private var isEditingTranscript = false
    @State private var editedTranscript = ""

    init(entry: VoiceEntry, secureFileStore: SecureFileStore, entryRepository: EntryRepository, projectRepository: ProjectRepository) {
        self._entry = State(initialValue: entry)
        self.secureFileStore = secureFileStore
        self.entryRepository = entryRepository
        self.projectRepository = projectRepository
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Project assignment
                projectSection

                Divider()

                // Transcript
                transcriptSection

                // Summary
                if !entry.summaryText.isEmpty {
                    Divider()
                    summarySection
                }

                // Tags
                if !entry.tags.isEmpty {
                    Divider()
                    tagsSection
                }

                // Action Items
                if !entry.actionItems.isEmpty {
                    Divider()
                    actionItemsSection
                }

                // People Mentioned
                if !entry.peopleMentioned.isEmpty {
                    Divider()
                    peopleMentionedSection
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle(entry.summaryTitle.isEmpty ? "Entry" : entry.summaryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            cleanupAudio()
        }
        .task {
            availableProjects = (try? await projectRepository.allProjects()) ?? []
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.createdAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Menu {
                    ForEach(Self.moodOptions, id: \.self) { mood in
                        Button {
                            Task { await updateMood(mood) }
                        } label: {
                            HStack {
                                Text(mood)
                                if entry.mood == mood {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Mood: \(entry.mood ?? "Not set")")
                            .font(.caption)
                            .italic()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            // Play audio button
            Button {
                togglePlayback()
            } label: {
                Label(
                    isPlayingAudio ? "Stop" : "Play",
                    systemImage: isPlayingAudio ? "stop.circle.fill" : "play.circle.fill"
                )
                .font(.title2)
            }

            Text(formatDuration(entry.durationSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var projectSection: some View {
        HStack {
            Label("Project", systemImage: "folder")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                Button {
                    Task { await updateProject(nil) }
                } label: {
                    HStack {
                        Text("None")
                        if entry.projectId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(availableProjects) { project in
                    Button {
                        Task { await updateProject(project.id) }
                    } label: {
                        HStack {
                            Text(project.name)
                            if entry.projectId == project.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentProjectName)
                        .font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var currentProjectName: String {
        guard let projectId = entry.projectId,
              let project = availableProjects.first(where: { $0.id == projectId }) else {
            return "None"
        }
        return project.name
    }

    private static let moodOptions = [
        "Great", "Happy", "Calm", "Grateful", "Excited", "Confident",
        "Okay", "Neutral", "Reflective", "Mixed",
        "Stressed", "Anxious", "Tired", "Frustrated", "Sad",
        "Angry", "Hopeless"
    ]

    private func updateMood(_ mood: String) async {
        var updated = entry
        updated.mood = mood
        do {
            try await entryRepository.update(updated)
            entry = updated
        } catch {}
    }

    private func updateProject(_ projectId: UUID?) async {
        var updated = entry
        updated.projectId = projectId
        do {
            try await entryRepository.update(updated)
            entry = updated
        } catch {
            // Silently fail — entry stays unchanged in the UI
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Full Transcript", systemImage: "text.quote")
                    .font(.headline)

                Spacer()

                if isEditingTranscript {
                    Button("Cancel") {
                        isEditingTranscript = false
                        editedTranscript = ""
                    }
                    .font(.subheadline)

                    Button("Save") {
                        Task { await saveTranscript() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button {
                        editedTranscript = entry.transcript
                        isEditingTranscript = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.subheadline)
                    }
                }
            }

            if isEditingTranscript {
                TextEditor(text: $editedTranscript)
                    .accessibilityLabel("Transcript")
                    .font(.body)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Text(entry.transcript)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private func saveTranscript() async {
        var updated = entry
        updated.transcript = editedTranscript
        do {
            try await entryRepository.update(updated)
            entry = updated
            isEditingTranscript = false
            editedTranscript = ""
        } catch {}
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("AI Summary", systemImage: "sparkles")
                .font(.headline)

            Text(entry.summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(cornerRadius: 16)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Tags", systemImage: "tag")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(entry.tags, id: \.self) { tag in
                    TagChip(text: tag)
                }
            }
        }
    }

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Action Items", systemImage: "checklist")
                .font(.headline)

            ForEach(entry.actionItems, id: \.self) { item in
                HStack(alignment: .top) {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.body)
                }
            }
        }
    }

    private var peopleMentionedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("People Mentioned", systemImage: "person.2")
                .font(.headline)

            ForEach(entry.peopleMentioned, id: \.self) { person in
                Text(person)
                    .font(.body)
            }
        }
    }

    // MARK: - Audio Playback

    private func togglePlayback() {
        if isPlayingAudio {
            audioPlayer?.stop()
            isPlayingAudio = false
            return
        }

        do {
            // Ensure audio routes to the speaker, not the earpiece
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let url = try secureFileStore.temporaryDecryptedURL(
                filename: entry.encryptedAudioFilename,
                keyVersion: entry.keyVersion
            )
            tempAudioURL = url
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.play()
            isPlayingAudio = true
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func cleanupAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        if let url = tempAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

}

// MARK: - Flow Layout for Tags

/// A simple flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        let itemProposal = ProposedViewSize(width: bounds.width, height: nil)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: itemProposal
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxRowHeight: CGFloat = 0

        for subview in subviews {
            // Propose the row width so an item wider than the row (a long tag
            // at a large text size) wraps instead of overflowing.
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += maxRowHeight + spacing
                maxRowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxRowHeight = max(maxRowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + maxRowHeight), positions)
    }
}
