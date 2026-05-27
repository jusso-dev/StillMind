import Foundation
import Speech
import AVFoundation

/// Performs fully on-device speech-to-text transcription using Apple's Speech framework.
/// No audio data is ever sent to Apple's servers.
///
/// The on-device recognizer struggles with audio longer than ~15 seconds,
/// so we split the audio into overlapping segments, transcribe each independently,
/// and stitch the results together with duplicate removal at boundaries.
final class TranscriptionService: @unchecked Sendable {

    /// Maximum segment duration in seconds. The on-device recognizer truncates
    /// anything much longer than this.
    private let segmentDuration: TimeInterval = 10
    /// Overlap between segments to avoid cutting mid-word.
    private let overlapDuration: TimeInterval = 2

    /// Requests speech recognition authorization.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Transcribes an audio file fully on-device by splitting it into overlapping segments.
    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer() else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }

        let asset = AVURLAsset(url: audioURL)
        let totalDuration = try await CMTimeGetSeconds(asset.load(.duration))

        // Short recordings — transcribe directly, no splitting needed
        if totalDuration <= segmentDuration + 1 {
            return try await transcribeSegment(audioURL, recognizer: recognizer)
        }

        // Split into overlapping segments
        let segmentURLs = try splitAudioFile(asset: asset, totalDuration: totalDuration)
        defer {
            for url in segmentURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Transcribe each segment
        var transcriptParts: [String] = []
        for segmentURL in segmentURLs {
            let text = try await transcribeSegment(segmentURL, recognizer: recognizer)
            if !text.isEmpty {
                transcriptParts.append(text)
            }
        }

        guard !transcriptParts.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        // Stitch segments together, removing duplicated words at overlap boundaries
        return stitchTranscripts(transcriptParts)
    }

    // MARK: - Segment Splitting

    /// Splits an audio file into overlapping segments.
    private func splitAudioFile(asset: AVURLAsset, totalDuration: TimeInterval) throws -> [URL] {
        var segmentURLs: [URL] = []
        let step = segmentDuration - overlapDuration
        var startTime: TimeInterval = 0

        while startTime < totalDuration {
            let endTime = min(startTime + segmentDuration, totalDuration)

            // Skip tiny trailing segments (< 1 second of actual new content)
            if endTime - startTime < 1.0 && !segmentURLs.isEmpty {
                break
            }

            let segmentURL = try exportSegment(
                from: asset,
                startTime: startTime,
                endTime: endTime,
                index: segmentURLs.count
            )
            segmentURLs.append(segmentURL)
            startTime += step
        }

        return segmentURLs
    }

    /// Exports a time range of an AVAsset to a new audio file.
    private func exportSegment(
        from asset: AVURLAsset,
        startTime: TimeInterval,
        endTime: TimeInterval,
        index: Int
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("segment-\(index)-\(UUID().uuidString).m4a")

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 44100),
            end: CMTime(seconds: endTime, preferredTimescale: 44100)
        )

        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.segmentExportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange

        exportSession.exportAsynchronously {
            if exportSession.status == .failed {
                exportError = exportSession.error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = exportError {
            throw error
        }

        return outputURL
    }

    // MARK: - Single Segment Transcription

    /// Transcribes a single short audio segment using on-device recognition.
    private func transcribeSegment(_ audioURL: URL, recognizer: SFSpeechRecognizer) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var bestTranscript = ""

            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let result {
                    bestTranscript = result.bestTranscription.formattedString

                    if result.isFinal {
                        hasResumed = true
                        continuation.resume(returning: bestTranscript)
                        return
                    }
                }

                if error != nil {
                    hasResumed = true
                    if !bestTranscript.isEmpty {
                        continuation.resume(returning: bestTranscript)
                    } else {
                        continuation.resume(returning: "")
                    }
                    return
                }
            }
        }
    }

    // MARK: - Overlap Stitching

    /// Joins transcribed segments by removing duplicated words at overlap boundaries.
    ///
    /// When segments overlap by 2 seconds, the end of segment N and the start of
    /// segment N+1 will contain the same spoken words. We find the longest matching
    /// sequence of trailing words from segment N that appear at the start of segment N+1,
    /// and remove the duplicate.
    private func stitchTranscripts(_ parts: [String]) -> String {
        guard parts.count > 1 else {
            return parts.first ?? ""
        }

        var result = parts[0]

        for i in 1..<parts.count {
            let nextPart = parts[i]
            let overlapRemoved = removeOverlap(previous: result, next: nextPart)
            result = overlapRemoved
        }

        return result
    }

    /// Finds overlapping words between the tail of `previous` and the head of `next`,
    /// then returns the merged string with the overlap removed.
    private func removeOverlap(previous: String, next: String) -> String {
        let prevWords = previous.split(separator: " ").map(String.init)
        let nextWords = next.split(separator: " ").map(String.init)

        guard !prevWords.isEmpty && !nextWords.isEmpty else {
            return [previous, next].filter { !$0.isEmpty }.joined(separator: " ")
        }

        // Check the last N words of previous against the first N words of next
        // (overlap is ~2 seconds of speech, roughly 4-8 words)
        let maxCheck = min(prevWords.count, nextWords.count, 12)
        var bestMatchLength = 0

        for matchLen in 1...maxCheck {
            let tailSlice = prevWords.suffix(matchLen).map { $0.lowercased() }
            let headSlice = nextWords.prefix(matchLen).map { $0.lowercased() }

            if tailSlice == headSlice {
                bestMatchLength = matchLen
            }
        }

        if bestMatchLength > 0 {
            // Remove the overlapping words from the start of next
            let trimmedNext = nextWords.dropFirst(bestMatchLength).joined(separator: " ")
            if trimmedNext.isEmpty {
                return previous
            }
            return previous + " " + trimmedNext
        }

        // No overlap found — just concatenate
        return previous + " " + next
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case onDeviceUnavailable
    case noSpeechDetected
    case segmentExportFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available on this device"
        case .onDeviceUnavailable:
            return "On-device speech recognition is not available. Please download the language in Settings > General > Keyboard > Dictation."
        case .noSpeechDetected:
            return "No speech was detected in the recording"
        case .segmentExportFailed:
            return "Failed to process audio for transcription"
        }
    }
}
