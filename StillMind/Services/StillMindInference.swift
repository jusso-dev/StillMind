import CoreML
import Foundation

// MARK: - StillMindTagger
//
// Usage:
//
//   let tagger = try StillMindTagger()
//   let result = try tagger.predict(text: "I had a really stressful day at work today.")
//   print("Tags:", result.tags)
//   print("Moods:", result.moods)
//
// Requirements:
//   - StillMindTagger.mlpackage in your Xcode target
//   - vocab.txt in your Xcode target (copy from models/stillmind-tagger/vocab.txt)

public struct TaggerResult {
    public let tags: [String]    // labels with probability >= threshold
    public let moods: [String]
    public let tagProbabilities: [String: Float]
    public let moodProbabilities: [String: Float]
}

public final class StillMindTagger {
    private let model: MLModel
    private let tokenizer: DistilBertTokenizer
    private let threshold: Float

    private static let tagLabels: [String] = ["family", "work", "health", "relationships", "finances", "memories", "grief", "goals", "gratitude", "conflict", "self_image", "parenting", "creativity", "spirituality", "loneliness"]
    private static let moodLabels: [String] = ["stressed", "anxious", "positive", "reflective", "sad", "angry", "calm", "hopeful", "overwhelmed", "numb", "grateful", "frustrated", "content", "fearful", "determined"]

    public init(threshold: Float = 0.5) throws {
        guard let modelURL = Bundle.main.url(forResource: "StillMindTagger", withExtension: "mlpackage") else {
            throw TaggerError.modelNotFound("StillMindTagger.mlpackage not found in bundle")
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        self.model = try MLModel(contentsOf: modelURL, configuration: config)

        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw TaggerError.vocabNotFound("vocab.txt not found in bundle")
        }
        self.tokenizer = try DistilBertTokenizer(vocabURL: vocabURL)
        self.threshold = threshold
    }

    public func predict(text: String) throws -> TaggerResult {
        let maxLength = 256
        let (inputIDs, attentionMask) = tokenizer.encode(text: text, maxLength: maxLength)

        let inputIDsArray = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)
        let maskArray    = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)

        for i in 0..<maxLength {
            inputIDsArray[i] = NSNumber(value: inputIDs[i])
            maskArray[i]     = NSNumber(value: attentionMask[i])
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: inputIDsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])

        let output = try model.prediction(from: input)

        let tagProbs  = extractProbs(from: output, key: "tag_probs",  count: Self.tagLabels.count)
        let moodProbs = extractProbs(from: output, key: "mood_probs", count: Self.moodLabels.count)

        let tags  = zip(Self.tagLabels,  tagProbs ).filter  { $0.1 >= threshold }.map { $0.0 }
        let moods = zip(Self.moodLabels, moodProbs).filter { $0.1 >= threshold }.map { $0.0 }

        let tagProbDict  = Dictionary(uniqueKeysWithValues: zip(Self.tagLabels,  tagProbs))
        let moodProbDict = Dictionary(uniqueKeysWithValues: zip(Self.moodLabels, moodProbs))

        return TaggerResult(
            tags: tags,
            moods: moods,
            tagProbabilities: tagProbDict,
            moodProbabilities: moodProbDict
        )
    }

    private func extractProbs(from output: MLFeatureProvider, key: String, count: Int) -> [Float] {
        guard let arr = output.featureValue(for: key)?.multiArrayValue else { return Array(repeating: 0, count: count) }
        return (0..<count).map { Float(truncating: arr[$0]) }
    }
}

// MARK: - TaggerError

public enum TaggerError: Error, LocalizedError {
    case modelNotFound(String)
    case vocabNotFound(String)
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let msg): return "Model not found: \(msg)"
        case .vocabNotFound(let msg): return "Vocab not found: \(msg)"
        case .encodingFailed(let msg): return "Encoding failed: \(msg)"
        }
    }
}

// MARK: - DistilBertTokenizer
//
// Self-contained WordPiece tokenizer. Loads vocab.txt from the app bundle.
// No third-party dependencies required.

public final class DistilBertTokenizer {
    private let vocab: [String: Int]
    private let ids: [Int: String]

    private static let clsToken = "[CLS]"
    private static let sepToken = "[SEP]"
    private static let padToken = "[PAD]"
    private static let unkToken = "[UNK]"

    public init(vocabURL: URL) throws {
        let contents = try String(contentsOf: vocabURL, encoding: .utf8)
        var vocab: [String: Int] = [:]
        var ids: [Int: String] = [:]
        for (idx, line) in contents.components(separatedBy: "\n").enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            vocab[token] = idx
            ids[idx] = token
        }
        self.vocab = vocab
        self.ids = ids
    }

    public func encode(text: String, maxLength: Int) -> ([Int32], [Int32]) {
        let tokens = tokenize(text: text)
        let clsID = vocab[Self.clsToken] ?? 101
        let sepID = vocab[Self.sepToken] ?? 102
        let padID = vocab[Self.padToken] ?? 0

        // Reserve 2 slots for [CLS] and [SEP]
        let truncated = Array(tokens.prefix(maxLength - 2))
        let ids: [Int] = [clsID] + truncated.map { vocab[$0] ?? (vocab[Self.unkToken] ?? 100) } + [sepID]

        var inputIDs = ids.map { Int32($0) }
        var attentionMask = Array(repeating: Int32(1), count: inputIDs.count)

        // Pad to maxLength
        let padCount = maxLength - inputIDs.count
        if padCount > 0 {
            inputIDs     += Array(repeating: Int32(padID), count: padCount)
            attentionMask += Array(repeating: Int32(0),   count: padCount)
        }

        return (inputIDs, attentionMask)
    }

    // MARK: WordPiece tokenization

    private func tokenize(text: String) -> [String] {
        let cleaned = basicTokenize(text: text)
        var tokens: [String] = []
        for word in cleaned {
            tokens += wordPiece(word: word)
        }
        return tokens
    }

    private func basicTokenize(text: String) -> [String] {
        // Lowercase, remove accents, split on whitespace and punctuation
        let lowered = text.lowercased()
        var result: [String] = []
        var current = ""

        for scalar in lowered.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else if isPunctuation(scalar) {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(scalar))
            } else {
                current.append(Character(scalar))
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func wordPiece(word: String) -> [String] {
        guard !word.isEmpty else { return [] }
        if word.count == 1 { return [vocab[word] != nil ? word : (vocab[Self.unkToken] != nil ? Self.unkToken : word)] }

        var subTokens: [String] = []
        var remaining = word
        var isFirst = true

        while !remaining.isEmpty {
            var found = false
            var end = remaining.endIndex
            while end > remaining.startIndex {
                let sub = isFirst ? String(remaining[..<end]) : "##" + remaining[..<end]
                if vocab[sub] != nil {
                    subTokens.append(sub)
                    remaining = String(remaining[end...])
                    isFirst = false
                    found = true
                    break
                }
                end = remaining.index(before: end)
            }
            if !found {
                return [Self.unkToken]
            }
        }
        return subTokens
    }

    private func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let cat = scalar.properties.generalCategory
        return [.connectorPunctuation, .dashPunctuation, .closePunctuation,
                .finalPunctuation, .initialPunctuation, .otherPunctuation,
                .openPunctuation].contains(cat)
    }
}
