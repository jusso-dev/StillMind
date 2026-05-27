import Foundation
import Security

/// Manages secure storage of encryption keys in the iOS Keychain.
/// Keys are device-only (no iCloud sync) and accessible only when the device is unlocked.
final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    private let serviceName = "com.stillmind.keychain"
    private let masterKeyAccount = "master-encryption-key"
    private let keyVersionAccount = "encryption-key-version"

    private init() {}

    // MARK: - Master Key Management

    /// Retrieves the current master encryption key, generating one on first launch.
    func getOrCreateMasterKey() throws -> Data {
        if let existing = try retrieveKey(account: masterKeyAccount) {
            return existing
        }
        // Generate a 256-bit key
        let newKey = generateRandomKey(sizeInBytes: 32)
        try storeKey(newKey, account: masterKeyAccount)
        // Initialize key version to 1
        try storeKeyVersion(1)
        return newKey
    }

    /// Returns the current key version number.
    func currentKeyVersion() throws -> Int {
        guard let data = try retrieveKey(account: keyVersionAccount),
              data.count == MemoryLayout<Int>.size else {
            return 1
        }
        return data.withUnsafeBytes { $0.load(as: Int.self) }
    }

    /// Rotates the master key: generates a new key, increments the version,
    /// and stores the old key under a versioned account for decrypting old entries.
    func rotateMasterKey() throws -> (newKey: Data, newVersion: Int) {
        let oldKey = try getOrCreateMasterKey()
        let oldVersion = try currentKeyVersion()

        // Archive the old key under its version
        let archivedAccount = "\(masterKeyAccount)-v\(oldVersion)"
        try storeKey(oldKey, account: archivedAccount)

        // Generate and store new key
        let newKey = generateRandomKey(sizeInBytes: 32)
        try deleteKey(account: masterKeyAccount)
        try storeKey(newKey, account: masterKeyAccount)

        let newVersion = oldVersion + 1
        try storeKeyVersion(newVersion)

        return (newKey, newVersion)
    }

    /// Retrieves a key for a specific version (used when decrypting old entries).
    func key(forVersion version: Int) throws -> Data {
        let currentVersion = try currentKeyVersion()
        if version == currentVersion {
            return try getOrCreateMasterKey()
        }
        let account = "\(masterKeyAccount)-v\(version)"
        guard let key = try retrieveKey(account: account) else {
            throw KeychainError.keyNotFound(version: version)
        }
        return key
    }

    // MARK: - Private Helpers

    private func generateRandomKey(sizeInBytes: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: sizeInBytes)
        let status = SecRandomCopyBytes(kSecRandomDefault, sizeInBytes, &bytes)
        precondition(status == errSecSuccess, "Failed to generate random bytes")
        return Data(bytes)
    }

    private func storeKey(_ keyData: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // Prevent iCloud sync
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status: status)
        }
    }

    private func retrieveKey(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unableToRetrieve(status: status)
        }
        return data
    }

    private func deleteKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status: status)
        }
    }

    private func storeKeyVersion(_ version: Int) throws {
        try? deleteKey(account: keyVersionAccount)
        var v = version
        let data = Data(bytes: &v, count: MemoryLayout<Int>.size)
        try storeKey(data, account: keyVersionAccount)
    }
}

enum KeychainError: LocalizedError {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)
    case unableToDelete(status: OSStatus)
    case keyNotFound(version: Int)

    var errorDescription: String? {
        switch self {
        case .unableToStore(let s): return "Keychain store failed: \(s)"
        case .unableToRetrieve(let s): return "Keychain retrieve failed: \(s)"
        case .unableToDelete(let s): return "Keychain delete failed: \(s)"
        case .keyNotFound(let v): return "Encryption key version \(v) not found"
        }
    }
}
