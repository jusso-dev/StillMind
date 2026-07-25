# StillMind

<img src="StillMind/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="StillMind app icon" width="112" height="112">

StillMind is a privacy-first voice journaling app for iOS. It records short
voice entries, transcribes them on device, summarizes them locally, organizes
them into projects, and stores sensitive data encrypted on the device.

The project is built with SwiftUI and is intended to be useful both as an app
and as a reference implementation for local-first, private journaling workflows.

## Features

### Private Voice Journaling

- Record voice entries with a live audio level visualization.
- Store recordings in encrypted local storage.
- Protect the journal behind Face ID with passcode fallback.
- Keep transcription and summarization on device.

### On-Device Transcription

- Uses Apple's Speech framework for local speech-to-text where supported.
- Records 16 kHz mono AAC audio optimized for on-device recognition.
- Splits longer recordings into overlapping segments and stitches transcripts.
- Requires the user to grant Speech Recognition permission.

### Local AI Summaries

- Generates extractive summaries from transcripts.
- Extracts structured fields such as title, summary, tags, action items,
  people mentioned, and mood.
- Uses a bundled Core ML package for tag and mood classification.

### Organization and Search

- Group entries into projects with names and descriptions.
- Search transcripts, summaries, and tags.
- Filter entries by project, tags, and dates.
- Review mood trends and weekly reflections.

### Backup and Export

- Create encrypted password-protected backups.
- Restore backups with conflict detection and re-encryption on the target
  device.
- Configure automatic nightly backups with retention.
- Export entries to PDF.

## Privacy Model

StillMind is designed around local-first storage:

- Journal content is stored on device.
- Audio files and entry metadata are encrypted at rest.
- Encryption keys are stored in the Keychain.
- Backup archives are encrypted with a user-provided password.
- Transcription and summarization are intended to run locally.

Contributors should not add analytics, cloud sync, remote transcription, remote
LLM calls, or crash reporting without explicit opt-in UX and documentation.

## Tech Stack

| Layer | Technology |
| --- | --- |
| Language | Swift |
| UI | SwiftUI |
| Audio | AVFoundation |
| Transcription | Apple Speech framework |
| Summaries and tags | Core ML, NaturalLanguage |
| Encryption | CryptoKit AES-GCM |
| Key storage | Security Keychain |
| Biometrics | LocalAuthentication |
| Background work | BackgroundTasks |
| Charts | Swift Charts |
| PDF export | UIKit PDF rendering |

Minimum deployment target: iOS 17.0.

## Architecture

The app follows an MVVM plus service architecture.

```text
StillMind/
├── App/                    # App entry point and root navigation
├── Models/                 # VoiceEntry, Project, StructuredSummary
├── Views/                  # SwiftUI screens and shared view styling
├── ViewModels/             # UI state and workflow orchestration
├── Services/               # Storage, encryption, transcription, backup, etc.
├── Assets.xcassets/        # App icon, launch logo, colors
├── StillMindTagger.mlpackage/
└── Info.plist
```

Core data flow:

```text
Microphone
  -> RecordingService
  -> SecureFileStore
  -> TranscriptionService
  -> SummarizationService
  -> EntryRepository
```

Important implementation details:

- `EntryRepository` and `ProjectRepository` are Swift actors.
- `SecureFileStore` encrypts audio before storing it under Documents.
- `EncryptionService` uses AES-GCM and supports key versioning.
- `NightlyBackupService` uses `BGTaskScheduler` plus app-background fallbacks.
- `TranscriptionService` uses Apple's on-device recognizer and overlapping
  segments for longer recordings.

## Requirements

- macOS with Xcode 15 or newer.
- iOS 17 or newer simulator or device.
- Git LFS for model and binary assets.

Install Git LFS before cloning or pulling assets:

```sh
git lfs install
```

## Build and Run

1. Clone the repository:

   ```sh
   git clone https://github.com/jusso-dev/StillMind.git
   cd StillMind
   git lfs pull
   ```

2. Open the Xcode project:

   ```sh
   open StillMind.xcodeproj
   ```

3. Select an iOS 17 or newer simulator.

4. Build and run.

The checked-in release configuration uses the Yarn Digi Apple development team
and bundle identifier `com.au.yarndigi.StillMind`. Contributors outside that
team should replace both values with ones they control.

## Model Assets

The repository includes local inference assets for tag and mood classification:

- `StillMind/StillMindTagger.mlpackage`
- `StillMind/vocab.txt`

Large binary assets are tracked with Git LFS. If Xcode reports missing model
files, run:

```sh
git lfs pull
```

See `THIRD_PARTY_NOTICES.md` for third-party source and licensing notes.

## Permissions

The app declares these user-facing permissions:

| Permission | Purpose |
| --- | --- |
| Microphone | Record voice journal entries |
| Speech Recognition | Transcribe voice journal entries on device |
| Face ID | Protect private journal content |

The app also declares the background task identifier
`com.au.yarndigi.StillMind.nightly-backup` for scheduled backup work.

## App Store release

Fastlane automates simulator compilation, App Store screenshots, TestFlight
uploads, metadata, signing, and release builds:

```sh
bundle install
bundle exec fastlane ios tests
bundle exec fastlane ios screenshots
bundle exec fastlane ios beta
```

See `fastlane/APP_STORE_CHECKLIST.md` for one-time Apple setup and the remaining
manual App Store Connect details. StillMind is configured as a free app with no
in-app purchases.

## Repository Hygiene

The repository intentionally excludes:

- Xcode `xcuserdata`.
- `.DS_Store` files.
- Provisioning profiles and signing certificates.
- Local environment files.
- Local assistant worktrees and editor state.
- Build outputs and derived data.

Do not commit real recordings, backups, exported PDFs, private keys, API keys,
or Apple signing material.

## Contributing

See `CONTRIBUTING.md` for setup, workflow, and privacy expectations.

## Security

See `SECURITY.md` for private vulnerability reporting guidance.

## License

StillMind is available under the MIT License. See `LICENSE` for details.
