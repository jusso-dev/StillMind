import XCTest

final class SnapshotTest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppStoreScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-StillMindSnapshotMode", "YES"]
        app.launch()

        waitFor(app.staticTexts["A calmer start"], screen: "Home")
        snapshot("01Home")

        let recordButton = app.buttons["Record a new voice journal entry"]
        waitFor(recordButton, screen: "Record button")
        recordButton.tap()
        waitFor(app.staticTexts["Speak your mind"], screen: "Recorder")
        snapshot("02Capture")

        let closeButton = app.buttons["Close"]
        waitFor(closeButton, screen: "Recorder close button")
        closeButton.tap()

        openTab("Journal", in: app)
        waitFor(app.navigationBars["Journal"], screen: "Journal")
        waitFor(app.staticTexts["A calmer start"], screen: "Journal content")
        snapshot("03Journal")

        app.staticTexts["A calmer start"].firstMatch.tap()
        waitFor(app.staticTexts["Full Transcript"], screen: "Entry detail")
        snapshot("04Reflection")

        if app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        openTab("Home", in: app)

        let insightsLink = app.staticTexts["Last 2 weeks"]
        waitFor(insightsLink, screen: "Insights link")
        insightsLink.tap()
        waitFor(app.navigationBars["Reflect"], screen: "Insights")
        snapshot("05Insights")
    }

    @MainActor
    private func waitFor(
        _ element: XCUIElement,
        timeout: TimeInterval = 12,
        screen: String
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(screen) to appear"
        )
    }

    @MainActor
    private func openTab(_ label: String, in app: XCUIApplication) {
        let tabButton = app.tabBars.buttons[label]
        if tabButton.waitForExistence(timeout: 4) {
            tabButton.tap()
            return
        }

        let fallbackButton = app.buttons[label].firstMatch
        waitFor(fallbackButton, timeout: 4, screen: "\(label) tab")
        fallbackButton.tap()
    }
}
