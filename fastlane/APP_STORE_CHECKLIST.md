# StillMind App Store checklist

## One-time Apple setup

- Create the App Store Connect app record for `com.au.yarndigi.StillMind`.
- Register the same App ID in the Apple Developer portal.
- Copy `fastlane/.env.sample` to `fastlane/.env` and fill in the API-key and match values.
- Run `bundle exec fastlane ios certs` once from a trusted Mac to create the App Store profile.
- Add the TestFlight GitHub environment secrets listed in `.github/workflows/testflight.yml`.

## Required public URLs

Publish privacy and support pages, then rename and update:

- `fastlane/metadata/en-AU/privacy_url.txt.sample` to `privacy_url.txt`
- `fastlane/metadata/en-AU/support_url.txt.sample` to `support_url.txt`
- `fastlane/metadata/en-AU/marketing_url.txt.sample` to `marketing_url.txt` (optional)

## App Store Connect answers

- Pricing: the release lanes set price tier `0` (Free).
- In-App Purchases: none.
- App Privacy: no tracking and no collected data; journal content remains on device.
- Export Compliance: `ITSAppUsesNonExemptEncryption` is set to `NO`.
- Category: Lifestyle.
- Complete the age-rating questionnaire and the EU trader-status declaration.
- Add review contact details. No demo account is required because StillMind has no sign-in.

## Commands

```sh
bundle install
bundle exec fastlane ios tests
bundle exec fastlane ios screenshots
bundle exec fastlane ios beta
bundle exec fastlane ios metadata
bundle exec fastlane ios release
```

`beta` uploads to TestFlight. `release` uploads the binary, metadata, and screenshots but deliberately does not submit for review or enable automatic release.
