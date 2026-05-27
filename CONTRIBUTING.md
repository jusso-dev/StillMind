# Contributing

Thanks for helping improve StillMind. This project is a SwiftUI iOS app focused
on private, on-device voice journaling.

## Development Setup

1. Install Xcode 15 or newer.
2. Clone the repository with Git LFS enabled:

   ```sh
   git lfs install
   git clone https://github.com/jusso-dev/StillMind.git
   cd StillMind
   git lfs pull
   ```

3. Open `StillMind.xcodeproj`.
4. Select an iOS 17 or newer simulator.
5. If you want to run on a physical device, set your own Apple development team
   and change the bundle identifier from the open-source placeholder.

## Pull Requests

- Keep changes focused and explain the user-facing impact.
- Do not commit personal Xcode state, provisioning profiles, signing
  certificates, local environment files, recordings, backups, or exported PDFs.
- Prefer existing MVVM and service patterns over introducing new architecture.
- Include screenshots or screen recordings for visible UI changes.
- Call out any changes that affect privacy, encryption, backup format,
  transcription, or model assets.

## Code Style

- Use Swift concurrency and actors where they fit the existing design.
- Keep services testable and avoid mixing persistence, UI, and platform APIs
  unless the current boundary already does so.
- Keep comments short and reserve them for non-obvious behavior.

## Privacy Expectations

StillMind is intended to run offline and keep journal data private. Contributions
must not add analytics, crash reporting, cloud sync, network transcription, or
remote model calls without a clear opt-in design and documentation.
