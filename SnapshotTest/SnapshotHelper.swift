import Foundation
import XCTest

private enum SnapshotHarness {
    static var screenshotsDirectory: URL?
}

@MainActor
func setupSnapshot(_ app: XCUIApplication) {
    guard let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
        NSLog("snapshot: SIMULATOR_HOST_HOME is unavailable")
        return
    }

    let cacheDirectory = URL(fileURLWithPath: hostHome)
        .appending(path: "Library/Caches/tools.fastlane", directoryHint: .isDirectory)
    SnapshotHarness.screenshotsDirectory = cacheDirectory
        .appending(path: "screenshots", directoryHint: .isDirectory)

    appendSetting(
        from: cacheDirectory.appending(path: "language.txt"),
        to: &app.launchArguments,
        key: "-AppleLanguages",
        transform: { "(\($0))" }
    )
    appendSetting(
        from: cacheDirectory.appending(path: "locale.txt"),
        to: &app.launchArguments,
        key: "-AppleLocale"
    )

    let argumentsURL = cacheDirectory.appending(path: "snapshot-launch_arguments.txt")
    if let arguments = try? String(contentsOf: argumentsURL, encoding: .utf8) {
        app.launchArguments.append(
            contentsOf: arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        )
    }
    app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]
}

@MainActor
func snapshot(_ name: String) {
    guard let outputDirectory = SnapshotHarness.screenshotsDirectory else {
        XCTFail("Snapshot output directory was not configured")
        return
    }

    Thread.sleep(forTimeInterval: 0.8)
    let screenshot = XCUIScreen.main.screenshot()
    var simulatorName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "Simulator"
    if let prefix = simulatorName.range(
        of: #"^Clone [0-9]+ of "#,
        options: .regularExpression
    ) {
        simulatorName.removeSubrange(prefix)
    }
    let outputURL = outputDirectory.appending(path: "\(simulatorName)-\(name).png")

    do {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try screenshot.pngRepresentation.write(to: outputURL, options: .atomic)
        NSLog("snapshot: wrote \(outputURL.path)")
    } catch {
        XCTFail("Could not write \(name): \(error.localizedDescription)")
    }
}

private func appendSetting(
    from url: URL,
    to arguments: inout [String],
    key: String,
    transform: (String) -> String = { $0 }
) {
    guard let value = try? String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
    else {
        return
    }
    arguments += [key, transform(value)]
}

// SnapshotHelperVersion [1.30]
