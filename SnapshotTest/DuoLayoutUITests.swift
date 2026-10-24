import XCTest

/// Layout checks for size changes such as iPhone Duo's 466×678 and 669×951 pt
/// displays. Rotation exercises window resizing; it does not replace a physical
/// fold/unfold check. Run on an iPhone Duo simulator with each display active.
final class DuoLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testRecorderActionStaysReachableInLandscapeWithKeyboard() {
        let app = launchSnapshotApp()
        XCUIDevice.shared.orientation = .landscapeLeft

        let recordButton = app.buttons["Record a new voice journal entry"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 12))
        recordButton.tap()

        let textMode = app.buttons["Text"]
        XCTAssertTrue(textMode.waitForExistence(timeout: 8))
        textMode.tap()

        let editor = app.textViews["Journal text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap()
        let draft = "Duo resize draft"
        editor.typeText(draft)

        let save = app.buttons["Save Entry"]
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertTrue(save.isHittable, "Save Entry is not reachable at \(orientation.rawValue)")
            XCTAssertEqual(editor.value as? String, draft, "Resizing lost the typed draft")
        }

        app.buttons["Close"].tap()
    }

    @MainActor
    func testInsightsKeepsSingleNavigationStackAcrossRotation() {
        let app = launchSnapshotApp()
        let insightsLink = app.staticTexts["Last 2 weeks"]
        XCTAssertTrue(insightsLink.waitForExistence(timeout: 12))
        insightsLink.tap()

        let reflect = app.navigationBars["Reflect"]
        XCTAssertTrue(reflect.waitForExistence(timeout: 8))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(reflect.waitForExistence(timeout: 5), "Resizing reset the Insights navigation")
            XCTAssertEqual(app.navigationBars.count, 1, "Insights should not nest a second navigation bar")
            // iOS 26+ hosts the back button outside the NavigationBar element.
            XCTAssertTrue(app.buttons["BackButton"].isHittable, "Back button is not reachable")
        }
    }

    @MainActor
    private func launchSnapshotApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-StillMindSnapshotMode", "YES"]
        app.launch()
        return app
    }
}
