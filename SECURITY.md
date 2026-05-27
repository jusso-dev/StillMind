# Security Policy

StillMind handles private journal content, encrypted backups, and locally stored
audio. Please report security issues privately instead of opening a public issue.

## Reporting a Vulnerability

Email the maintainer or use GitHub private vulnerability reporting if it is
enabled for this repository. Include:

- A description of the issue and affected area.
- Steps to reproduce or a proof of concept.
- The expected impact.
- Any relevant device, iOS, or Xcode versions.

Please do not include real journal entries, real recordings, passwords, private
keys, or other sensitive personal data in reports.

## Scope

High-priority areas include:

- Encryption and key management.
- Backup creation and restore.
- Decrypted temporary audio files.
- Biometric lock behavior.
- Transcription model loading.
- Accidental network access or data exfiltration.

## Supported Versions

The `main` branch is the active development line. Security fixes should target
`main` unless a release branch is introduced.
