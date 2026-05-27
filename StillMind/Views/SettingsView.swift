import SwiftUI
import UserNotifications

/// Privacy and security settings screen.
struct SettingsView: View {
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository
    let backupService: BackupService
    let nightlyBackupService: NightlyBackupService
    let notificationService: NotificationService
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @State private var showingPanicLockConfirmation = false
    @State private var showingPDFExport = false
    @State private var dataDeleted = false
    @State private var isCreatingBackup = false
    @State private var backupShareURL: URL?
    @State private var showingBackupShare = false
    @State private var showingRestorePicker = false
    @State private var backupStatus: BackupStatus?

    // Password prompts
    @State private var showingBackupPassword = false
    @State private var showingRestorePassword = false
    @State private var backupPassword = ""
    @State private var backupPasswordConfirm = ""
    @State private var restorePassword = ""
    @State private var pendingRestoreURL: URL?

    // Daily reminder
    @State private var dailyReminderEnabled = false
    @State private var reminderTime = Date()
    @State private var notificationPermissionDenied = false

    // Nightly backup
    @State private var nightlyBackupEnabled = false
    @State private var showingNightlyFolderPicker = false
    @State private var showingNightlyPasswordPrompt = false
    @State private var nightlyPassword = ""
    @State private var nightlyPasswordConfirm = ""
    @State private var nightlyHasFolder = false
    @State private var nightlyHasPassword = false
    @State private var nightlyRetainCount = 7
    @State private var nightlyLastStatus: String?
    @State private var nightlyLastDate: Date?
    @State private var isRunningManualNightly = false

    var body: some View {
        NavigationStack {
            List {
                Section("Security") {
                    Toggle("Require Face ID / Touch ID", isOn: $requireBiometrics)
                }

                Section {
                    Toggle("Daily Journal Reminder", isOn: $dailyReminderEnabled)
                        .onChange(of: dailyReminderEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let granted = await notificationService.requestPermission()
                                    if granted {
                                        notificationService.isEnabled = true
                                    } else {
                                        dailyReminderEnabled = false
                                        notificationPermissionDenied = true
                                    }
                                }
                            } else {
                                notificationService.isEnabled = false
                            }
                        }

                    if dailyReminderEnabled {
                        DatePicker(
                            "Reminder Time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: reminderTime) { _, newTime in
                            notificationService.reminderTime = newTime
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Get a daily reminder to record a voice journal entry. The notification is automatically dismissed when you record.")
                }

                Section {
                    Button {
                        backupPassword = ""
                        backupPasswordConfirm = ""
                        showingBackupPassword = true
                    } label: {
                        HStack {
                            Label("Create Encrypted Backup", systemImage: "arrow.up.doc.fill")
                            Spacer()
                            if isCreatingBackup {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCreatingBackup)
                    .sheet(isPresented: $showingBackupShare) {
                        if let url = backupShareURL {
                            ShareSheet(items: [url])
                        }
                    }

                    Button {
                        showingRestorePicker = true
                    } label: {
                        Label("Restore from Backup", systemImage: "arrow.down.doc.fill")
                    }
                    .fileImporter(
                        isPresented: $showingRestorePicker,
                        allowedContentTypes: [.data],
                        allowsMultipleSelection: false
                    ) { result in
                        handleRestoreFileSelected(result: result)
                    }
                } header: {
                    Text("Backup & Restore")
                } footer: {
                    Text("Backups are encrypted with a password you choose. Save to Files for local storage or iCloud Drive for cloud backup.")
                }

                if let status = backupStatus {
                    Section {
                        Label(status.message, systemImage: status.icon)
                            .foregroundStyle(status.isError ? .red : .green)
                    }
                }

                Section {
                    Toggle("Enable Nightly Backup", isOn: $nightlyBackupEnabled)
                        .onChange(of: nightlyBackupEnabled) { _, enabled in
                            if enabled && nightlyHasFolder && nightlyHasPassword {
                                nightlyBackupService.isEnabled = true
                            } else if !enabled {
                                nightlyBackupService.isEnabled = false
                            }
                        }

                    if nightlyBackupEnabled {
                        Button {
                            showingNightlyFolderPicker = true
                        } label: {
                            HStack {
                                Label(
                                    nightlyHasFolder ? "Change Backup Folder" : "Choose Backup Folder",
                                    systemImage: "folder.badge.gearshape"
                                )
                                Spacer()
                                if nightlyHasFolder {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .fileImporter(
                            isPresented: $showingNightlyFolderPicker,
                            allowedContentTypes: [.folder],
                            allowsMultipleSelection: false
                        ) { result in
                            handleNightlyFolderSelected(result: result)
                        }

                        Button {
                            nightlyPassword = ""
                            nightlyPasswordConfirm = ""
                            showingNightlyPasswordPrompt = true
                        } label: {
                            HStack {
                                Label(
                                    nightlyHasPassword ? "Change Backup Password" : "Set Backup Password",
                                    systemImage: "key.fill"
                                )
                                Spacer()
                                if nightlyHasPassword {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }

                        Stepper("Keep last \(nightlyRetainCount) backups", value: $nightlyRetainCount, in: 1...30)
                            .onChange(of: nightlyRetainCount) { _, newValue in
                                nightlyBackupService.retainCount = newValue
                            }

                        Button {
                            isRunningManualNightly = true
                            Task {
                                let success = await nightlyBackupService.performNightlyBackup()
                                isRunningManualNightly = false
                                refreshNightlyStatus()
                                backupStatus = BackupStatus(
                                    message: success ? "Nightly backup completed." : "Nightly backup failed.",
                                    icon: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    isError: !success
                                )
                            }
                        } label: {
                            HStack {
                                Label("Run Backup Now", systemImage: "arrow.clockwise")
                                Spacer()
                                if isRunningManualNightly {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(!nightlyHasFolder || !nightlyHasPassword || isRunningManualNightly)

                        if let date = nightlyLastDate {
                            HStack {
                                Text("Last backup")
                                Spacer()
                                Text(date, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let status = nightlyLastStatus {
                            HStack {
                                Text("Status")
                                Spacer()
                                Text(status)
                                    .foregroundStyle(status == "Success" ? .green : .red)
                            }
                        }
                    }
                } header: {
                    Text("Automatic Nightly Backup")
                } footer: {
                    Text("Automatically creates an encrypted backup every night and saves it to your chosen folder. Old backups are pruned automatically.")
                }

                Section("Data") {
                    Button("Export Journal as PDF") {
                        showingPDFExport = true
                    }

                    Button("Delete All Data", role: .destructive) {
                        showingPanicLockConfirmation = true
                    }
                }

                if dataDeleted {
                    Section {
                        Label("All data has been deleted.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Encryption")
                        Spacer()
                        Text("AES-256-GCM")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Data Storage")
                        Spacer()
                        Text("On-Device Only")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data?", isPresented: $showingPanicLockConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    Task { await panicLock() }
                }
            } message: {
                Text("This permanently deletes all journal entries, recordings, and encryption keys. This cannot be undone.")
            }
            .alert("Set Backup Password", isPresented: $showingBackupPassword) {
                SecureField("Password", text: $backupPassword)
                SecureField("Confirm Password", text: $backupPasswordConfirm)
                Button("Cancel", role: .cancel) {
                    backupPassword = ""
                    backupPasswordConfirm = ""
                }
                Button("Create Backup") {
                    let pw = backupPassword
                    backupPassword = ""
                    backupPasswordConfirm = ""
                    Task { await createBackup(password: pw) }
                }
                .disabled(backupPassword.count < 6 || backupPassword != backupPasswordConfirm)
            } message: {
                Text("Choose a password to protect your backup (min 6 characters).")
            }
            .alert("Enter Backup Password", isPresented: $showingRestorePassword) {
                SecureField("Password", text: $restorePassword)
                Button("Cancel", role: .cancel) {
                    restorePassword = ""
                    if let url = pendingRestoreURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    pendingRestoreURL = nil
                }
                Button("Restore") {
                    let pw = restorePassword
                    let url = pendingRestoreURL
                    restorePassword = ""
                    pendingRestoreURL = nil
                    if let url {
                        Task { await performRestore(url: url, password: pw) }
                    }
                }
            } message: {
                Text("Enter the password you used when creating this backup.")
            }
            .sheet(isPresented: $showingPDFExport) {
                PDFExportView(entryRepository: entryRepository, projectRepository: projectRepository)
            }
            .alert("Set Nightly Backup Password", isPresented: $showingNightlyPasswordPrompt) {
                SecureField("Password", text: $nightlyPassword)
                SecureField("Confirm Password", text: $nightlyPasswordConfirm)
                Button("Cancel", role: .cancel) {
                    nightlyPassword = ""
                    nightlyPasswordConfirm = ""
                }
                Button("Save") {
                    let pw = nightlyPassword
                    nightlyPassword = ""
                    nightlyPasswordConfirm = ""
                    do {
                        try nightlyBackupService.savePassword(pw)
                        nightlyHasPassword = true
                        if nightlyHasFolder {
                            nightlyBackupService.isEnabled = true
                        }
                    } catch {
                        backupStatus = BackupStatus(
                            message: "Failed to save password: \(error.localizedDescription)",
                            icon: "exclamationmark.triangle.fill",
                            isError: true
                        )
                    }
                }
                .disabled(nightlyPassword.count < 6 || nightlyPassword != nightlyPasswordConfirm)
            } message: {
                Text("This password will be stored securely in your device Keychain and used to encrypt nightly backups (min 6 characters).")
            }
            .alert("Notifications Disabled", isPresented: $notificationPermissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enable notifications for StillMind in Settings → Notifications to receive daily journal reminders.")
            }
            .onAppear {
                dailyReminderEnabled = notificationService.isEnabled
                reminderTime = notificationService.reminderTime
                nightlyBackupEnabled = nightlyBackupService.isEnabled
                nightlyHasFolder = nightlyBackupService.hasFolder
                nightlyHasPassword = nightlyBackupService.hasPassword
                nightlyRetainCount = nightlyBackupService.retainCount
                refreshNightlyStatus()
            }
        }
    }

    // MARK: - Backup

    private func createBackup(password: String) async {
        isCreatingBackup = true
        backupStatus = nil
        do {
            let url = try await backupService.createBackup(password: password)
            backupShareURL = url
            showingBackupShare = true
            backupStatus = BackupStatus(
                message: "Backup created. Save to Files or iCloud Drive.",
                icon: "checkmark.circle.fill",
                isError: false
            )
        } catch {
            backupStatus = BackupStatus(
                message: "Backup failed: \(error.localizedDescription)",
                icon: "exclamationmark.triangle.fill",
                isError: true
            )
        }
        isCreatingBackup = false
    }

    // MARK: - Restore

    private func handleRestoreFileSelected(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            // Copy file immediately while security scope is active
            _ = url.startAccessingSecurityScopedResource()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pending_restore_\(UUID().uuidString).tmp")
            try FileManager.default.copyItem(at: url, to: tempURL)
            url.stopAccessingSecurityScopedResource()

            pendingRestoreURL = tempURL
            restorePassword = ""
            showingRestorePassword = true
        } catch {
            backupStatus = BackupStatus(
                message: "Could not open file: \(error.localizedDescription)",
                icon: "exclamationmark.triangle.fill",
                isError: true
            )
        }
    }

    private func performRestore(url: URL, password: String) async {
        backupStatus = nil
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let r = try await backupService.restoreBackup(from: url, password: password)
            backupStatus = BackupStatus(
                message: "Restored \(r.entriesRestored) entries, \(r.projectsRestored) projects, \(r.audioFilesRestored)/\(r.audioFilesInBackup) audio files.",
                icon: "checkmark.circle.fill",
                isError: false
            )
        } catch {
            backupStatus = BackupStatus(
                message: "Restore failed: \(error.localizedDescription)",
                icon: "exclamationmark.triangle.fill",
                isError: true
            )
        }
    }

    // MARK: - Nightly Backup

    private func handleNightlyFolderSelected(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            try nightlyBackupService.saveFolder(url: url)
            url.stopAccessingSecurityScopedResource()
            nightlyHasFolder = true
            if nightlyHasPassword {
                nightlyBackupService.isEnabled = true
            }
        } catch {
            backupStatus = BackupStatus(
                message: "Could not save folder: \(error.localizedDescription)",
                icon: "exclamationmark.triangle.fill",
                isError: true
            )
        }
    }

    private func refreshNightlyStatus() {
        nightlyLastDate = nightlyBackupService.lastBackupDate
        nightlyLastStatus = nightlyBackupService.lastBackupStatus
    }

    // MARK: - Panic Lock

    private func panicLock() async {
        try? await entryRepository.deleteAll()
        try? await projectRepository.deleteAll()

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.removeItem(at: docs.appendingPathComponent("EncryptedAudio"))

        dataDeleted = true
    }
}

// MARK: - Helpers

private struct BackupStatus {
    let message: String
    let icon: String
    let isError: Bool
}
