import BackgroundTasks
import SwiftUI

@main
struct StillMindApp: App {
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isUnlocked = false
    @State private var launchFinished = false
    @Environment(\.scenePhase) private var scenePhase

    // Service dependencies — created once and shared
    private let encryptionService: EncryptionService
    private let secureFileStore: SecureFileStore
    private let entryRepository: EntryRepository
    private let projectRepository: ProjectRepository
    private let transcriptionService: TranscriptionService
    private let recordingService: RecordingService
    private let searchService: SearchService
    private let backupService: BackupService
    private let nightlyBackupService: NightlyBackupService
    private let notificationService: NotificationService

    init() {
        let encryption = EncryptionService()
        self.encryptionService = encryption
        let fileStore = SecureFileStore(encryptionService: encryption)
        self.secureFileStore = fileStore
        let entries = EntryRepository(encryptionService: encryption)
        self.entryRepository = entries
        let projects = ProjectRepository()
        self.projectRepository = projects
        self.transcriptionService = TranscriptionService()
        self.recordingService = RecordingService()
        self.searchService = SearchService(repository: entries, projectRepository: projects)
        let backup = BackupService(
            encryptionService: encryption,
            entryRepository: entries,
            projectRepository: projects,
            secureFileStore: fileStore
        )
        self.backupService = backup
        let nightlyBackup = NightlyBackupService(backupService: backup)
        nightlyBackup.registerBackgroundTask()
        self.nightlyBackupService = nightlyBackup
        self.notificationService = NotificationService()

        // If nightly backup was previously enabled, re-schedule on launch
        if nightlyBackup.isEnabled {
            nightlyBackup.scheduleNextBackup()
        }

        // Re-schedule daily reminder if previously enabled
        if notificationService.isEnabled {
            notificationService.scheduleDailyReminder()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(
                recordingService: recordingService,
                transcriptionService: transcriptionService,
                encryptionService: encryptionService,
                secureFileStore: secureFileStore,
                entryRepository: entryRepository,
                projectRepository: projectRepository,
                searchService: searchService,
                backupService: backupService,
                nightlyBackupService: nightlyBackupService,
                notificationService: notificationService
            )
            .overlay {
                if requireBiometrics && !isUnlocked {
                    LockScreenView(isUnlocked: $isUnlocked)
                        .transition(.opacity)
                }
            }
            .overlay {
                if !launchFinished {
                    LaunchView(isFinished: $launchFinished)
                }
            }
            .overlay {
                if launchFinished && !hasCompletedOnboarding {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Catch-up: if the BGProcessingTask didn't fire overnight,
                // run the backup now when the user opens the app.
                nightlyBackupService.performBackupIfOverdue()
            case .background:
                if requireBiometrics {
                    isUnlocked = false
                }
                // Fallback: request ~30s of background time from UIKit
                // to run a backup if one is overdue.
                nightlyBackupService.performBackupOnBackground()
            default:
                break
            }
        }
    }
}

/// Main tab-based navigation.
struct MainTabView: View {
    let secureFileStore: SecureFileStore
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository
    let searchService: SearchService
    let backupService: BackupService
    let nightlyBackupService: NightlyBackupService
    let notificationService: NotificationService

    // ViewModels persisted via @State — never recreated on body re-evaluation
    @State private var recordViewModel: RecordViewModel
    @State private var entryListViewModel: EntryListViewModel
    @State private var projectListViewModel: ProjectListViewModel

    init(
        recordingService: RecordingService,
        transcriptionService: TranscriptionService,
        encryptionService: EncryptionService,
        secureFileStore: SecureFileStore,
        entryRepository: EntryRepository,
        projectRepository: ProjectRepository,
        searchService: SearchService,
        backupService: BackupService,
        nightlyBackupService: NightlyBackupService,
        notificationService: NotificationService
    ) {
        self.secureFileStore = secureFileStore
        self.entryRepository = entryRepository
        self.projectRepository = projectRepository
        self.searchService = searchService
        self.backupService = backupService
        self.nightlyBackupService = nightlyBackupService
        self.notificationService = notificationService

        self._recordViewModel = State(initialValue: RecordViewModel(
            recordingService: recordingService,
            transcriptionService: transcriptionService,
            encryptionService: encryptionService,
            secureFileStore: secureFileStore,
            entryRepository: entryRepository,
            projectRepository: projectRepository,
            notificationService: notificationService
        ))
        self._entryListViewModel = State(initialValue: EntryListViewModel(
            entryRepository: entryRepository
        ))
        self._projectListViewModel = State(initialValue: ProjectListViewModel(
            projectRepository: projectRepository,
            entryRepository: entryRepository
        ))
    }

    var body: some View {
        TabView {
            HomeView(
                entryRepository: entryRepository,
                projectRepository: projectRepository,
                secureFileStore: secureFileStore,
                recordViewModel: recordViewModel
            )
            .tabItem {
                Label("Home", systemImage: "house")
            }

            EntryListView(
                viewModel: entryListViewModel,
                projectViewModel: projectListViewModel,
                secureFileStore: secureFileStore,
                entryRepository: entryRepository,
                projectRepository: projectRepository
            )
            .tabItem {
                Label("Journal", systemImage: "book")
            }

            SettingsView(
                entryRepository: entryRepository,
                projectRepository: projectRepository,
                backupService: backupService,
                nightlyBackupService: nightlyBackupService,
                notificationService: notificationService
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(Color.smAccent)
    }
}
