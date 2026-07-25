import SwiftUI

/// Immersive recording experience, presented as a fullScreenCover from HomeView.
struct RecordView: View {
    @Bindable var viewModel: RecordViewModel
    @Binding var isPresented: Bool

    @State private var availableProjects: [Project] = []
    @State private var breatheAnimation = false
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Center content — changes based on recording state
                    centerContent
                        .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Bottom action area
                    bottomArea
                        .padding(.bottom, Spacing.xxl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.state == .idle || viewModel.state == .complete || viewModel.state == .reviewing {
                        projectMenu
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark.circle.fill") {
                        handleDismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .opacity(viewModel.state == .recording ? 0.3 : 1)
                    .disabled(viewModel.state == .recording)
                }
            }
            .task {
                availableProjects = await viewModel.availableProjects()
                await viewModel.refreshEntryCount()
            }
            .alert("We're here for you", isPresented: $viewModel.showingSafetyAlert) {
                Link("Call Lifeline (\(SafetyService.lifelineNumber))",
                     destination: URL(string: "tel:\(SafetyService.lifelineNumber.replacingOccurrences(of: " ", with: ""))")!)
                Button("OK", role: .cancel) { }
            } message: {
                Text(SafetyService.supportMessage)
            }
        }
    }

    // MARK: - Center Content

    @ViewBuilder
    private var centerContent: some View {
        switch viewModel.state {
        case .idle:
            idleContent
        case .recording:
            recordingContent
        case .transcribing:
            processingContent(
                icon: "waveform.badge.mic",
                title: "Listening...",
                subtitle: "Transcribing your words"
            )
        case .reviewing:
            reviewingContent
        case .summarizing:
            processingContent(
                icon: "sparkles",
                title: "Reflecting...",
                subtitle: "Understanding your thoughts"
            )
        case .saving:
            processingContent(
                icon: "lock.shield",
                title: "Securing...",
                subtitle: "Encrypting & saving"
            )
        case .complete:
            completeContent
        case .error(let message):
            errorContent(message: message)
        }
    }

    // MARK: - Idle State

    private var idleContent: some View {
        VStack(spacing: Spacing.lg) {
            // Mode picker
            Picker("Input mode", selection: $viewModel.inputMode) {
                Label("Voice", systemImage: "mic.fill").tag(RecordViewModel.InputMode.voice)
                Label("Text", systemImage: "keyboard").tag(RecordViewModel.InputMode.text)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            if viewModel.inputMode == .voice {
                // Subtle breathing — slow opacity pulse, scoped so nothing else moves
                Image(systemName: "mic.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.smAccent)
                    .modifier(BreathingOpacity(active: breatheAnimation))
                    .onAppear { breatheAnimation = true }

                Text("Speak your mind")
                    .font(.title2.weight(.medium))

                Text("Your thoughts are encrypted and never leave this device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("\(Int(RecordViewModel.minRecordingDuration))s min · \(formatDuration(RecordViewModel.maxRecordingDuration)) max")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "text.cursor")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.smAccent)

                Text("Write your thoughts")
                    .font(.title2.weight(.medium))

                TextEditor(text: $viewModel.textInput)
                    .focused($isTextEditorFocused)
                    .frame(minHeight: 120, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.md)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        if viewModel.textInput.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(.tertiary)
                                .padding(Spacing.md)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    // MARK: - Recording State

    private var recordingContent: some View {
        VStack(spacing: Spacing.lg) {
            // Waveform
            AudioLevelView(level: viewModel.audioLevel)
                .frame(height: 64)
                .accessibilityHidden(true)

            // Timer
            Text(formatDuration(viewModel.recordingDuration))
                .font(.system(.largeTitle, design: .monospaced, weight: .light))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.05), value: viewModel.recordingDuration)

            // Minimum duration hint
            if !viewModel.canStopRecording {
                Text("Keep going — \(Int(RecordViewModel.minRecordingDuration - viewModel.recordingDuration))s left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            ProgressView(
                value: viewModel.recordingDuration,
                total: RecordViewModel.maxRecordingDuration
            )
            .tint(viewModel.remainingSeconds < 10 ? .red : Color.smAccent)
            .accessibilityLabel("Recording progress")
            .accessibilityValue("\(Int(viewModel.recordingDuration)) of \(Int(RecordViewModel.maxRecordingDuration)) seconds")
        }
    }

    // MARK: - Processing States

    private func processingContent(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.smAccent)
                .symbolEffect(.pulse.byLayer, options: .repeating)

            Text(title)
                .font(.title2.weight(.medium))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Show transcript as it appears
            if !viewModel.transcript.isEmpty {
                ScrollView {
                    Text(viewModel.transcript)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                }
                .frame(maxHeight: 120)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 16))
            }
        }
    }

    // MARK: - Reviewing State

    private var reviewingContent: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "pencil.line")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.smAccent)

            Text("Review transcript")
                .font(.title2.weight(.medium))

            Text("Edit anything the transcription got wrong")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $viewModel.transcript)
                .frame(minHeight: 120, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(Spacing.md)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 16))
        }
    }

    // MARK: - Complete State

    private var completeContent: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.smAccent)

            Text("Saved securely")
                .font(.title2.weight(.medium))

            // Summary card
            if let summary = viewModel.summary {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(summary.title)
                        .font(.headline)

                    Text(summary.shortSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !summary.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                ForEach(summary.tags, id: \.self) { tag in
                                    TagChip(text: tag)
                                }
                            }
                        }
                    }

                    if let mood = summary.mood {
                        MoodPill(mood: mood)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
        .onAppear { Haptics.success() }
    }

    // MARK: - Error State

    private func errorContent(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title3.weight(.medium))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Bottom Area

    private var bottomArea: some View {
        VStack(spacing: Spacing.md) {
            switch viewModel.state {
            case .idle:
                if viewModel.inputMode == .voice {
                    recordButton(isRecording: false)
                } else {
                    Button {
                        isTextEditorFocused = false
                        Haptics.medium()
                        viewModel.submitText()
                    } label: {
                        Label("Save Entry", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.smAccent)
                    .controlSize(.large)
                    .disabled(viewModel.textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .recording:
                recordButton(isRecording: true)
            case .reviewing:
                Button {
                    Haptics.medium()
                    viewModel.confirmTranscript()
                } label: {
                    Label("Looks Good", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.smAccent)
                .controlSize(.large)
                .disabled(viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .transcribing, .summarizing, .saving:
                ProgressView()
                    .tint(Color.smAccent)
            case .complete:
                Button {
                    Haptics.light()
                    handleDismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.smAccent)
                .controlSize(.large)

                Button("Record Another") {
                    viewModel.reset()
                }
                .font(.subheadline)
                .foregroundStyle(Color.smAccent)
            case .error:
                Button {
                    viewModel.reset()
                } label: {
                    Text("Try Again")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.smAccent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Record Button

    private func recordButton(isRecording: Bool) -> some View {
        Button {
            if isRecording {
                Haptics.medium()
                viewModel.stopRecording()
            } else {
                Haptics.medium()
                let projectId = viewModel.selectedProjectId
                viewModel.reset()
                viewModel.selectedProjectId = projectId
                viewModel.startRecording()
            }
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(isRecording ? Color.red.opacity(0.3) : Color.smAccent.opacity(0.3), lineWidth: 3)
                    .frame(width: 96, height: 96)

                // Fill
                Circle()
                    .fill(isRecording ? Color.red : Color.smAccent)
                    .frame(width: 80, height: 80)
                    .shadow(color: (isRecording ? Color.red : Color.smAccent).opacity(0.3), radius: 16)

                // Icon
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(!viewModel.canStartNewRecording && !isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Project Menu

    private var projectMenu: some View {
        Menu {
            Button {
                viewModel.selectedProjectId = nil
            } label: {
                HStack {
                    Text("No Project")
                    if viewModel.selectedProjectId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            ForEach(availableProjects) { project in
                Button {
                    viewModel.selectedProjectId = project.id
                } label: {
                    HStack {
                        Text(project.name)
                        if viewModel.selectedProjectId == project.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selectedProjectName, systemImage: "folder")
                .font(.subheadline)
        }
    }

    private var selectedProjectName: String {
        guard let id = viewModel.selectedProjectId,
              let project = availableProjects.first(where: { $0.id == id }) else {
            return "No Project"
        }
        return project.name
    }

    // MARK: - Helpers

    private func handleDismiss() {
        if viewModel.state == .complete || viewModel.state == .idle || viewModel.state == .reviewing {
            viewModel.reset()
        }
        isPresented = false
    }
}

// MARK: - Audio Level Waveform

/// Organic audio level visualization.
struct AudioLevelView: View {
    let level: Float
    private let barCount = 40

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let normalizedIndex = Float(index) / Float(barCount)
                let barHeight = calculateBarHeight(index: normalizedIndex, level: level)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.smAccent.opacity(Double(0.3 + level * 0.7)))
                    .frame(width: 3, height: CGFloat(barHeight))
            }
        }
        .animation(.easeOut(duration: 0.06), value: level)
    }

    private func calculateBarHeight(index: Float, level: Float) -> Float {
        let center = Float(0.5)
        let distance = abs(index - center)
        let baseHeight: Float = 3
        let maxAdditional: Float = 56
        let amplitude = max(0, level - distance)
        return baseHeight + amplitude * maxAdditional
    }
}

// MARK: - Breathing Opacity

/// Isolates a repeating opacity animation so it cannot leak to parent layout.
private struct BreathingOpacity: ViewModifier {
    let active: Bool

    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .opacity(phase ? 1.0 : 0.45)
            .onChange(of: active) { _, isActive in
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}
