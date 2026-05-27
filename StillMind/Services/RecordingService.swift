import AVFoundation
import Combine

/// Manages audio recording using AVFoundation.
/// Records to a temporary file in AAC format.
final class RecordingService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var currentTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    /// The URL of the most recent recording (temporary, plaintext).
    var lastRecordingURL: URL? { recordingURL }

    /// Configures the audio session for recording.
    func setupSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    /// Starts recording audio to a temporary file.
    func startRecording() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")

        // 16kHz mono is optimal for the on-device speech recognizer
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self

        guard recorder.record() else {
            throw RecordingError.failedToStart
        }

        self.audioRecorder = recorder
        self.recordingURL = url
        self.isRecording = true
        self.currentTime = 0

        // Update metering on main thread
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            self.currentTime = recorder.currentTime
            // Normalize power level from -160..0 dB to 0..1
            let power = recorder.averagePower(forChannel: 0)
            self.audioLevel = max(0, (power + 50) / 50)
        }
    }

    /// Stops the current recording. Returns the duration in seconds.
    func stopRecording() -> Double {
        let duration = audioRecorder?.currentTime ?? 0
        audioRecorder?.stop()
        audioRecorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        currentTime = 0
        audioLevel = 0
        return duration
    }
}

extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            isRecording = false
        }
    }
}

enum RecordingError: LocalizedError {
    case failedToStart
    var errorDescription: String? { "Audio recording failed to start" }
}
