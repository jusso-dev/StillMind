import Foundation
import Observation

/// Orchestrates the recording flow: record → transcribe → summarize → encrypt → save.
@Observable
@MainActor
final class RecordViewModel {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        /// Paused after transcription so the user can review/edit the transcript.
        case reviewing
        case summarizing
        case saving
        case complete
        case error(String)
    }

    enum InputMode {
        case voice
        case text
    }

    /// Minimum recording duration in seconds.
    nonisolated static let minRecordingDuration: TimeInterval = 5
    /// Maximum recording duration in seconds.
    nonisolated static let maxRecordingDuration: TimeInterval = 300

    var state: State = .idle
    var inputMode: InputMode = .voice
    var audioLevel: Float = 0
    var recordingDuration: TimeInterval = 0
    var partialTranscript: String = ""
    var transcript: String = ""
    /// User-typed text for text-only entries.
    var textInput: String = ""
    var summary: StructuredSummary?
    /// The project to assign the new entry to (nil = unassigned).
    var selectedProjectId: UUID?

    private let recordingService: RecordingService
    private let transcriptionService: TranscriptionService
    private let encryptionService: EncryptionService
    private let secureFileStore: SecureFileStore
    private let entryRepository: EntryRepository
    private let projectRepository: ProjectRepository
    private let notificationService: NotificationService?

    @ObservationIgnored private var meteringTimer: Timer?
    @ObservationIgnored private let taggingService = TaggingService()
    @ObservationIgnored private let safetyService = SafetyService()

    /// Set to `true` when crisis language is detected so the view can
    /// present a supportive alert with Lifeline Australia details.
    var showingSafetyAlert = false

    /// Current total entry count.
    var entryCount: Int = 0

    /// Remaining seconds before the recording auto-stops.
    var remainingSeconds: TimeInterval {
        max(0, Self.maxRecordingDuration - recordingDuration)
    }

    init(
        recordingService: RecordingService,
        transcriptionService: TranscriptionService,
        encryptionService: EncryptionService,
        secureFileStore: SecureFileStore,
        entryRepository: EntryRepository,
        projectRepository: ProjectRepository,
        notificationService: NotificationService? = nil
    ) {
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.encryptionService = encryptionService
        self.secureFileStore = secureFileStore
        self.entryRepository = entryRepository
        self.projectRepository = projectRepository
        self.notificationService = notificationService
    }

    /// Refreshes the current entry count from the repository.
    func refreshEntryCount() async {
        entryCount = ((try? await entryRepository.allEntries()) ?? []).count
    }

    // MARK: - Recording Controls

    func startRecording() {
        do {
            try recordingService.setupSession()
            try recordingService.startRecording()
            state = .recording
            transcript = ""
            partialTranscript = ""
            summary = nil

            // Mirror audio level and auto-stop at max duration
            meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.audioLevel = self.recordingService.audioLevel
                    self.recordingDuration = self.recordingService.currentTime
                    // Auto-stop at max recording duration
                    if self.recordingDuration >= Self.maxRecordingDuration {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Whether the recording is long enough to stop.
    var canStopRecording: Bool {
        recordingDuration >= Self.minRecordingDuration
    }

    /// Whether a new recording can be started (idle, complete, or error states).
    var canStartNewRecording: Bool {
        switch state {
        case .idle, .complete, .error:
            return true
        default:
            return false
        }
    }

    func stopRecording() {
        guard canStopRecording else {
            state = .error("Recording must be at least \(Int(Self.minRecordingDuration)) seconds")
            // Keep recording — don't stop
            return
        }

        meteringTimer?.invalidate()
        meteringTimer = nil
        let duration = recordingService.stopRecording()

        guard let audioURL = recordingService.lastRecordingURL else {
            state = .error("No recording file found")
            return
        }

        Task {
            await processRecording(audioURL: audioURL, duration: duration)
        }
    }

    // MARK: - Processing Pipeline

    /// Audio URL and duration stored between transcription and finalization for voice entries.
    @ObservationIgnored private var pendingAudioURL: URL?
    @ObservationIgnored private var pendingDuration: Double = 0

    private func processRecording(audioURL: URL, duration: Double) async {
        // Step 1: Transcribe
        state = .transcribing
        do {
            let transcriptText = try await transcriptionService.transcribe(audioURL: audioURL)
            self.transcript = transcriptText

            // Pause so the user can review/edit the transcript
            pendingAudioURL = audioURL
            pendingDuration = duration
            state = .reviewing
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Confirms the (possibly edited) transcript and continues the pipeline.
    func confirmTranscript() {
        guard state == .reviewing else { return }
        let editedTranscript = transcript
        let audioURL = pendingAudioURL
        let duration = pendingDuration

        Task {
            await finalize(transcript: editedTranscript, audioURL: audioURL, duration: duration)
        }
    }

    /// Submits a text-only entry (no audio recording).
    func submitText() {
        guard !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error("Please enter some text before saving")
            return
        }
        let text = textInput
        Task {
            await finalize(transcript: text, audioURL: nil, duration: 0)
        }
    }

    /// Shared finalization: summarize → (optionally encrypt audio) → save.
    private func finalize(transcript: String, audioURL: URL?, duration: Double) async {
        do {
            // Classify tags and moods with Core ML (fast, on-device)
            let (detectedTags, detectedMoods) = taggingService.classify(transcript: transcript)

            // Summarize (LLM path uses Core ML results as context hints)
            state = .summarizing
            let service = SummarizationService()
            let summaryResult = try await service.summarize(
                transcript: transcript,
                detectedTags: detectedTags,
                detectedMoods: detectedMoods
            )
            self.summary = summaryResult

            // Encrypt and store audio if present
            state = .saving
            var filename = ""
            var keyVer = 0
            if let audioURL {
                let result = try await secureFileStore.storeAudioFile(from: audioURL)
                filename = result.0
                keyVer = result.1
            }

            // Save entry
            let entry = VoiceEntry(
                durationSeconds: duration,
                encryptedAudioFilename: filename,
                transcript: transcript,
                summaryTitle: summaryResult.title,
                summaryText: summaryResult.shortSummary,
                tags: summaryResult.tags,
                actionItems: summaryResult.actionItems,
                peopleMentioned: summaryResult.peopleMentioned,
                mood: summaryResult.mood,
                keyVersion: keyVer,
                projectId: selectedProjectId
            )
            try await entryRepository.save(entry)

            // Dismiss today's reminder since the user just journaled
            notificationService?.dismissTodayReminder()

            // Surface crisis-support resources when appropriate
            if safetyService.detectsCrisisLanguage(in: transcript) {
                showingSafetyAlert = true
            }

            state = .complete
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
        audioLevel = 0
        recordingDuration = 0
        partialTranscript = ""
        transcript = ""
        textInput = ""
        summary = nil
        selectedProjectId = nil
        pendingAudioURL = nil
        pendingDuration = 0
    }

    /// Loads all available projects for the picker.
    func availableProjects() async -> [Project] {
        (try? await projectRepository.allProjects()) ?? []
    }
}
