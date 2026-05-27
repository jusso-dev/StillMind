import Foundation

/// Manages encrypted audio file storage on disk with NSFileProtectionComplete.
final class SecureFileStore: @unchecked Sendable {
    private let encryptionService: EncryptionService
    private let storageDirectory: URL

    init(encryptionService: EncryptionService) {
        self.encryptionService = encryptionService

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageDirectory = documentsDir.appendingPathComponent("EncryptedAudio", isDirectory: true)

        // Create directory if needed with complete file protection
        if !FileManager.default.fileExists(atPath: storageDirectory.path) {
            try? FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
    }

    /// Encrypts and stores an audio file. Returns the filename used for storage.
    func storeAudioFile(from sourceURL: URL) async throws -> (filename: String, keyVersion: Int) {
        let plainData = try Data(contentsOf: sourceURL)
        let encrypted = try encryptionService.encrypt(plainData)
        let keyVersion = try encryptionService.currentKeyVersion()

        let filename = UUID().uuidString + ".enc"
        let destinationURL = storageDirectory.appendingPathComponent(filename)

        try encrypted.write(to: destinationURL, options: .completeFileProtection)

        // Delete the plaintext source file
        try? FileManager.default.removeItem(at: sourceURL)

        return (filename, keyVersion)
    }

    /// Retrieves and decrypts an audio file, returning the raw audio data.
    func retrieveAudioData(filename: String, keyVersion: Int) throws -> Data {
        let fileURL = storageDirectory.appendingPathComponent(filename)
        let encrypted = try Data(contentsOf: fileURL)
        return try encryptionService.decrypt(encrypted, keyVersion: keyVersion)
    }

    /// Writes decrypted audio to a temporary file for playback. Caller is responsible for cleanup.
    func temporaryDecryptedURL(filename: String, keyVersion: Int) throws -> URL {
        let audioData = try retrieveAudioData(filename: filename, keyVersion: keyVersion)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension(for: audioData))
        try audioData.write(to: tempURL, options: .completeFileProtection)
        return tempURL
    }

    private func fileExtension(for audioData: Data) -> String {
        if audioData.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return "wav"
        }

        if audioData.count >= 8 && Array(audioData[4..<8]) == [0x66, 0x74, 0x79, 0x70] {
            return "m4a"
        }

        return "audio"
    }

    /// Deletes an encrypted audio file from disk.
    func deleteAudioFile(filename: String) throws {
        let fileURL = storageDirectory.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Reads the raw encrypted data for a file (used for backups — no decryption).
    func retrieveEncryptedData(filename: String) throws -> Data {
        let fileURL = storageDirectory.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }

    /// Writes raw encrypted data for a file (used for restoring backups — no encryption).
    func storeEncryptedData(_ data: Data, filename: String) throws {
        ensureDirectoryExists()
        let destinationURL = storageDirectory.appendingPathComponent(filename)
        try data.write(to: destinationURL, options: .completeFileProtection)
    }

    /// Takes raw (decrypted) audio data, encrypts it, and stores it.
    /// Returns the key version used. Used during backup restore.
    func storeRawAudioData(_ rawAudio: Data, filename: String) throws -> Int {
        ensureDirectoryExists()
        let encrypted = try encryptionService.encrypt(rawAudio)
        let keyVersion = try encryptionService.currentKeyVersion()
        let destinationURL = storageDirectory.appendingPathComponent(filename)
        try encrypted.write(to: destinationURL, options: .completeFileProtection)
        return keyVersion
    }

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: storageDirectory.path) {
            try? FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
    }
}
