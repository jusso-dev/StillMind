import Foundation
import cactus

/// Performs on-device speech-to-text transcription with the Cactus Swift SDK.
///
/// Cactus expects either a 16-bit PCM WAV file path or 16 kHz mono PCM bytes.
/// `RecordingService` records directly to a compatible WAV file, so this service
/// can send the saved recording path directly to the SDK.
final class TranscriptionService: @unchecked Sendable {
    private let modelLocator: CactusTranscriptionModelLocator
    private let optionsJSON: String?

    init(
        modelLocator: CactusTranscriptionModelLocator = .default,
        optionsJSON: String? = #"{"use_vad":false}"#
    ) {
        self.modelLocator = modelLocator
        self.optionsJSON = optionsJSON
    }

    /// Cactus transcription does not require Speech framework authorization.
    func requestAuthorization() async -> Bool {
        true
    }

    func transcribe(audioURL: URL) async throws -> String {
        let modelURL = try modelLocator.modelURL()
        let modelPath = modelURL.path
        let audioPath = audioURL.path
        let optionsJSON = optionsJSON

        return try await Task.detached(priority: .userInitiated) {
            let resultJSON = try CactusTranscriptionRuntime.shared.transcribe(
                audioPath: audioPath,
                modelPath: modelPath,
                optionsJSON: optionsJSON
            )
            return try CactusTranscriptionResponse(json: resultJSON).transcript
        }.value
    }
}

struct CactusTranscriptionModelLocator: Sendable {
    static let `default` = CactusTranscriptionModelLocator(
        resourceName: "CactusTranscriptionModel"
    )

    let resourceName: String

    func modelURL() throws -> URL {
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: nil) {
            return bundledURL
        }

        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(resourceName, isDirectory: true)

        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            return appSupportURL
        }

        throw TranscriptionError.modelNotFound(resourceName)
    }
}

private final class CactusTranscriptionRuntime: @unchecked Sendable {
    static let shared = CactusTranscriptionRuntime()

    private let lock = NSLock()
    private var modelPath: String?
    private var model: UnsafeMutableRawPointer?

    deinit {
        if let model {
            cactus_destroy(model)
        }
    }

    func transcribe(audioPath: String, modelPath: String, optionsJSON: String?) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let handle = try modelHandle(at: modelPath)
        var buffer = [CChar](repeating: 0, count: 1 << 20)

        let result = buffer.withUnsafeMutableBufferPointer { bufferPtr in
            cactus_transcribe(
                handle,
                audioPath,
                nil,
                bufferPtr.baseAddress,
                bufferPtr.count,
                optionsJSON,
                nil,
                nil,
                nil,
                0
            )
        }

        if result < 0 {
            throw TranscriptionError.cactusFailure(lastError(fallback: "Cactus transcription failed"))
        }

        return String(cString: buffer)
    }

    private func modelHandle(at path: String) throws -> UnsafeMutableRawPointer {
        if let model, modelPath == path {
            return model
        }

        if let model {
            cactus_destroy(model)
        }

        guard let loadedModel = cactus_init(path, nil, false) else {
            throw TranscriptionError.cactusFailure(lastError(fallback: "Failed to initialize Cactus transcription model"))
        }

        model = loadedModel
        modelPath = path
        return loadedModel
    }

    private func lastError(fallback: String) -> String {
        let message = String(cString: cactus_get_last_error())
        return message.isEmpty ? fallback : message
    }
}

private struct CactusTranscriptionResponse: Decodable {
    struct Segment: Decodable {
        let text: String
    }

    let success: Bool?
    let error: String?
    let response: String?
    let segments: [Segment]?

    init(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw TranscriptionError.invalidResponse("Cactus returned non-UTF8 transcription output")
        }

        do {
            self = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse("Cactus returned invalid transcription JSON")
        }

        if success == false {
            throw TranscriptionError.cactusFailure(error ?? "Cactus transcription failed")
        }
    }

    var transcript: String {
        get throws {
            if let response = response?.trimmingCharacters(in: .whitespacesAndNewlines),
               !response.isEmpty {
                return response
            }

            let segmentText = segments?
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !segmentText.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            return segmentText
        }
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotFound(String)
    case cactusFailure(String)
    case invalidResponse(String)
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let resourceName):
            return "Cactus transcription model '\(resourceName)' was not found in the app bundle or Application Support."
        case .cactusFailure(let message):
            return message
        case .invalidResponse(let message):
            return message
        case .noSpeechDetected:
            return "No speech was detected in the recording"
        }
    }
}
