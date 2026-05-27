import BackgroundTasks
import Foundation
import UIKit
import os

/// Manages automatic nightly backups using BGTaskScheduler with reliable fallbacks.
///
/// BGProcessingTask is best-effort on iOS and may not fire even when the device
/// is idle and charging. To guarantee daily backups, this service also:
/// - Checks for overdue backups every time the app becomes active
/// - Attempts a backup when the app moves to background (using beginBackgroundTask)
final class NightlyBackupService: @unchecked Sendable {
    static let taskIdentifier = "com.stillmind.nightly-backup"

    private let backupService: BackupService
    private let logger = Logger(subsystem: "com.stillmind", category: "NightlyBackup")

    // UserDefaults keys
    private static let enabledKey = "nightlyBackupEnabled"
    private static let bookmarkKey = "nightlyBackupFolderBookmark"
    private static let lastBackupDateKey = "nightlyBackupLastDate"
    private static let lastBackupStatusKey = "nightlyBackupLastStatus"
    private static let retainCountKey = "nightlyBackupRetainCount"

    // Keychain
    private static let keychainService = "com.stillmind.nightly-backup"
    private static let keychainAccount = "backup-password"

    /// Guards against concurrent backup runs from multiple triggers.
    private let backupLock = NSLock()
    private var isBackupRunning = false

    init(backupService: BackupService) {
        self.backupService = backupService
    }

    // MARK: - Configuration

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                scheduleNextBackup()
            } else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            }
        }
    }

    var retainCount: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Self.retainCountKey)
            return value > 0 ? value : 7
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: Self.retainCountKey) }
    }

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastBackupDateKey) as? Date
    }

    var lastBackupStatus: String? {
        UserDefaults.standard.string(forKey: Self.lastBackupStatusKey)
    }

    var hasFolder: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    var hasPassword: Bool {
        (try? retrievePassword()) != nil
    }

    /// True if nightly backup is enabled and no successful backup in the last 24 hours.
    var isBackupOverdue: Bool {
        guard isEnabled, hasFolder, hasPassword else { return false }
        guard let last = lastBackupDate else { return true }
        // Also consider overdue if last attempt failed
        let lastWasSuccess = lastBackupStatus == "Success"
        let hoursSinceLast = Date().timeIntervalSince(last) / 3600
        if !lastWasSuccess && hoursSinceLast > 1 { return true }
        return hoursSinceLast >= 24
    }

    // MARK: - Folder Bookmark

    /// Persist a security-scoped bookmark so we can access the user's chosen folder in the background.
    func saveFolder(url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkKey)
    }

    /// Resolve the persisted bookmark back to a URL. Caller must call
    /// `stopAccessingSecurityScopedResource()` when done.
    func resolveFolder() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            throw NightlyBackupError.noFolderConfigured
        }
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
        if isStale {
            // Re-save refreshed bookmark
            try saveFolder(url: url)
        }
        return url
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    // MARK: - Password (Keychain)

    func savePassword(_ password: String) throws {
        let data = Data(password.utf8)

        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NightlyBackupError.keychainError(status)
        }
    }

    func clearPassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func retrievePassword() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw NightlyBackupError.noPasswordConfigured
        }
        return password
    }

    // MARK: - BGTaskScheduler Registration

    /// Call once from app init to register the background task handler.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(processingTask)
        }
    }

    /// Schedule the next nightly backup. Safe to call multiple times.
    func scheduleNextBackup() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 2
        components.minute = 0
        var scheduledDate = calendar.date(from: components) ?? Date()
        if scheduledDate <= Date() {
            scheduledDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? Date()
        }
        request.earliestBeginDate = scheduledDate
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Nightly backup scheduled for \(scheduledDate)")
        } catch {
            logger.error("Failed to schedule nightly backup: \(error.localizedDescription)")
        }
    }

    // MARK: - Fallback Triggers

    /// Call when the app becomes active. Runs a backup if overdue.
    func performBackupIfOverdue() {
        guard isBackupOverdue else { return }
        logger.info("Backup is overdue — running catch-up backup on foreground")
        Task {
            await performNightlyBackup()
        }
    }

    /// Call when the app moves to background. Requests background execution time
    /// from UIKit (~30s) to run a backup if overdue.
    func performBackupOnBackground() {
        guard isBackupOverdue else { return }
        logger.info("Backup is overdue — attempting backup during background transition")
        let app = UIApplication.shared
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = app.beginBackgroundTask(withName: "StillMindNightlyBackup") {
            // Expiration handler — clean up
            if backgroundTaskID != .invalid {
                app.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        guard backgroundTaskID != .invalid else { return }
        Task {
            await performNightlyBackup()
            await MainActor.run {
                app.endBackgroundTask(backgroundTaskID)
            }
        }
    }

    // MARK: - Execution

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        // Schedule the next one immediately
        scheduleNextBackup()

        let backupTask = Task {
            let success = await performNightlyBackup()
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            backupTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Perform the backup. Returns true on success. Thread-safe — concurrent calls are no-ops.
    func performNightlyBackup() async -> Bool {
        // Prevent concurrent runs from multiple triggers
        backupLock.lock()
        if isBackupRunning {
            backupLock.unlock()
            logger.info("Backup already in progress, skipping")
            return false
        }
        isBackupRunning = true
        backupLock.unlock()

        defer {
            backupLock.lock()
            isBackupRunning = false
            backupLock.unlock()
        }

        logger.info("Starting nightly backup")

        do {
            let password = try retrievePassword()
            let folderURL = try resolveFolder()

            guard folderURL.startAccessingSecurityScopedResource() else {
                throw NightlyBackupError.folderAccessDenied
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }

            // Create the encrypted backup
            let tempURL = try await backupService.createBackup(password: password)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Copy to user's chosen folder
            let destURL = folderURL.appendingPathComponent(tempURL.lastPathComponent)
            try FileManager.default.copyItem(at: tempURL, to: destURL)

            // Prune old backups beyond retain count
            pruneOldBackups(in: folderURL)

            let now = Date()
            UserDefaults.standard.set(now, forKey: Self.lastBackupDateKey)
            UserDefaults.standard.set("Success", forKey: Self.lastBackupStatusKey)
            logger.info("Nightly backup completed successfully")
            return true
        } catch {
            UserDefaults.standard.set(
                "Failed: \(error.localizedDescription)",
                forKey: Self.lastBackupStatusKey
            )
            UserDefaults.standard.set(Date(), forKey: Self.lastBackupDateKey)
            logger.error("Nightly backup failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Pruning

    private func pruneOldBackups(in folderURL: URL) {
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            let backups = contents
                .filter { $0.pathExtension == BackupService.fileExtension }
                .filter { $0.lastPathComponent.hasPrefix("StillMind_Backup_") }
                .sorted { a, b in
                    let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return dateA > dateB  // newest first
                }

            // Keep only `retainCount` most recent
            if backups.count > retainCount {
                for old in backups.dropFirst(retainCount) {
                    try? fm.removeItem(at: old)
                    logger.info("Pruned old backup: \(old.lastPathComponent)")
                }
            }
        } catch {
            logger.warning("Could not prune old backups: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum NightlyBackupError: LocalizedError {
    case noFolderConfigured
    case noPasswordConfigured
    case folderAccessDenied
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noFolderConfigured:
            return "No backup folder selected. Please choose a folder in Settings."
        case .noPasswordConfigured:
            return "No backup password set. Please set a password in Settings."
        case .folderAccessDenied:
            return "Cannot access the backup folder. Please re-select it in Settings."
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}

