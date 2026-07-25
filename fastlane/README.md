fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios certs

```sh
[bundle exec] fastlane ios certs
```

Generate or sync the App Store certificate and provisioning profile

### ios tests

```sh
[bundle exec] fastlane ios tests
```

Compile the app for an iOS Simulator without signing

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture and frame the required iPhone and iPad App Store screenshots

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload a new TestFlight build without submitting it

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload metadata and fresh screenshots, and keep the app free

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload the complete free App Store release without auto-submission

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
