import CryptoKit
import Foundation

/// Manages backup and restore of all app data.
/// Uses binary plist for packaging (handles Data natively, no base64).
/// Backup stores DECRYPTED audio so it's portable across devices.
/// The entire backup is encrypted with a user-provided password.
final class BackupService: @unchecked Sendable {
    private let encryptionService: EncryptionService
    private let entryRepository: EntryRepository
    private let projectRepository: ProjectRepository
    private let secureFileStore: SecureFileStore

    static let fileExtension = "stillmindbackup"

    init(
        encryptionService: EncryptionService,
        entryRepository: EntryRepository,
        projectRepository: ProjectRepository,
        secureFileStore: SecureFileStore
    ) {
        self.encryptionService = encryptionService
        self.entryRepository = entryRepository
        self.projectRepository = projectRepository
        self.secureFileStore = secureFileStore
    }

    // MARK: - Backup

    func createBackup(password: String) async throws -> URL {
        let entries = try await entryRepository.allEntries()
        let projects = try await projectRepository.allProjects()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let entriesData = try encoder.encode(entries)
        let projectsData = try encoder.encode(projects)

        // DECRYPT audio from device storage to raw audio bytes.
        // This makes the backup portable (not tied to device keychain).
        var audioDict: [String: Data] = [:]
        for entry in entries {
            do {
                let rawAudio = try secureFileStore.retrieveAudioData(
                    filename: entry.encryptedAudioFilename,
                    keyVersion: entry.keyVersion
                )
                audioDict[entry.encryptedAudioFilename] = rawAudio
            } catch {
                // Audio file missing or can't decrypt — skip this one
                continue
            }
        }

        // Package everything into a binary plist (handles Data natively)
        let backup: [String: Any] = [
            "version": 1,
            "entries": entriesData,
            "projects": projectsData,
            "audio": audioDict
        ]

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: backup,
            format: .binary,
            options: 0
        )

        // Encrypt the plist with the password
        let salt = generateSalt()
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plistData, using: key)
        guard let encrypted = sealed.combined else {
            throw BackupError.backupFailed
        }

        // File = [32 bytes salt][encrypted plist]
        var output = Data()
        output.append(salt)
        output.append(encrypted)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "StillMind_Backup_\(formatter.string(from: Date())).\(Self.fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: tempURL)
        try output.write(to: tempURL)

        return tempURL
    }

    // MARK: - Restore

    func restoreBackup(from url: URL, password: String) async throws -> RestoreResult {
        let fileData = try Data(contentsOf: url)
        guard fileData.count > 32 else { throw BackupError.invalidFile }

        // Decrypt
        let salt = Data(fileData.prefix(32))
        let encrypted = Data(fileData.dropFirst(32))
        let key = deriveKey(password: password, salt: salt)
        let plistData: Data
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            plistData = try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.wrongPassword
        }

        guard let backup = try PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        ) as? [String: Any] else {
            throw BackupError.invalidFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Extract audio files with defensive casting
        var audioDict: [String: Data] = [:]
        if let audioAny = backup["audio"] {
            if let directCast = audioAny as? [String: Data] {
                audioDict = directCast
            } else if let anyDict = audioAny as? [String: Any] {
                for (key, value) in anyDict {
                    if let data = value as? Data {
                        audioDict[key] = data
                    }
                }
            }
        }

        // Restore entries
        var entriesRestored = 0
        var audioFilesRestored = 0
        if let entriesData = backup["entries"] as? Data {
            let entries = try decoder.decode([VoiceEntry].self, from: entriesData)
            let existing = try await entryRepository.allEntries()
            var existingIds = Set<UUID>()
            for e in existing { existingIds.insert(e.id) }

            for entry in entries where !existingIds.contains(entry.id) {
                var restoredEntry = entry

                // Re-encrypt the raw audio with this device's key
                if let rawAudio = audioDict[entry.encryptedAudioFilename] {
                    let newKeyVersion = try secureFileStore.storeRawAudioData(
                        rawAudio,
                        filename: entry.encryptedAudioFilename
                    )
                    restoredEntry.keyVersion = newKeyVersion
                    audioFilesRestored += 1
                }

                try await entryRepository.save(restoredEntry)
                entriesRestored += 1
            }
        }

        // Restore projects
        var projectsRestored = 0
        if let projectsData = backup["projects"] as? Data {
            let projects = try decoder.decode([Project].self, from: projectsData)
            let existing = try await projectRepository.allProjects()
            var existingIds = Set<UUID>()
            for p in existing { existingIds.insert(p.id) }

            for project in projects where !existingIds.contains(project.id) {
                try await projectRepository.save(project)
                projectsRestored += 1
            }
        }

        return RestoreResult(
            entriesRestored: entriesRestored,
            projectsRestored: projectsRestored,
            audioFilesRestored: audioFilesRestored,
            audioFilesInBackup: audioDict.count
        )
    }

    // MARK: - Crypto

    private func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let pwData = Data(password.utf8)
        let hash = SHA256.hash(data: pwData + salt)
        let inputKey = SymmetricKey(data: hash)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("StillMind-Backup-v1".utf8),
            outputByteCount: 32
        )
    }
}

// MARK: - Models

struct RestoreResult {
    let entriesRestored: Int
    let projectsRestored: Int
    let audioFilesRestored: Int
    let audioFilesInBackup: Int
}

enum BackupError: LocalizedError {
    case invalidFile
    case backupFailed
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "The backup file is invalid or corrupted."
        case .backupFailed: return "Failed to create backup."
        case .wrongPassword: return "Incorrect password. Please try again."
        }
    }
}
