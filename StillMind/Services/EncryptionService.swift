import Foundation
import CryptoKit

/// Provides AES-256-GCM encryption and decryption using keys from the Keychain.
final class EncryptionService: @unchecked Sendable {
    private let keychainService: KeychainService

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    /// Encrypts data using the current master key.
    /// Returns the encrypted data with the nonce and tag prepended.
    func encrypt(_ plainData: Data) throws -> Data {
        let keyData = try keychainService.getOrCreateMasterKey()
        let symmetricKey = SymmetricKey(data: keyData)

        let sealedBox = try AES.GCM.seal(plainData, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealingFailed
        }
        return combined
    }

    /// Decrypts data that was encrypted with the specified key version.
    func decrypt(_ encryptedData: Data, keyVersion: Int) throws -> Data {
        let keyData = try keychainService.key(forVersion: keyVersion)
        let symmetricKey = SymmetricKey(data: keyData)

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    /// Encrypts a string using the current master key.
    func encryptString(_ plainText: String) throws -> Data {
        guard let data = plainText.data(using: .utf8) else {
            throw EncryptionError.encodingFailed
        }
        return try encrypt(data)
    }

    /// Decrypts data back to a string.
    func decryptString(_ encryptedData: Data, keyVersion: Int) throws -> String {
        let decrypted = try decrypt(encryptedData, keyVersion: keyVersion)
        guard let text = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.decodingFailed
        }
        return text
    }

    /// Returns the current key version for tagging new entries.
    func currentKeyVersion() throws -> Int {
        try keychainService.currentKeyVersion()
    }
}

enum EncryptionError: LocalizedError {
    case sealingFailed
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .sealingFailed: return "AES-GCM sealing failed"
        case .encodingFailed: return "UTF-8 encoding failed"
        case .decodingFailed: return "UTF-8 decoding failed"
        }
    }
}
