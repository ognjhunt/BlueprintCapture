import XCTest

final class CorePathUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingScenarioShowsGetStarted() throws {
        let app = configuredApp(scenario: "onboarding")
        app.launch()

        XCTAssertTrue(app.buttons["onboarding-get-started"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testOnboardingScenarioShowsAuthEntryPoints() throws {
        let app = configuredApp(scenario: "onboarding")
        app.launch()

        let getStarted = app.buttons["onboarding-get-started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.tap()

        XCTAssertTrue(app.buttons["auth-sign-in"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["auth-create-account"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["auth-email"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCorePathScenarioStartsCaptureAndShowsUploadOverlay() throws {
        let app = configuredApp(scenario: "corePath")
        app.launch()

        let approvedFeatured = app.buttons["scan-home-featured-ui_test_job_approved"]
        XCTAssertTrue(approvedFeatured.waitForExistence(timeout: 10))
        approvedFeatured.tap()

        let stopButton = app.buttons["scan-recording-stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        stopButton.tap()

        let uploadOverlay = app.buttons["upload-overlay-compact"]
        XCTAssertTrue(uploadOverlay.waitForExistence(timeout: 10))
    }

    @MainActor
    func testCorePathScenarioUploadFromRecordingReturnsToVisibleUploadProgress() throws {
        let app = configuredApp(scenario: "corePath")
        app.launch()

        let approvedFeatured = app.buttons["scan-home-featured-ui_test_job_approved"]
        XCTAssertTrue(approvedFeatured.waitForExistence(timeout: 10))
        approvedFeatured.tap()

        let stopButton = app.buttons["scan-recording-stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        stopButton.tap()

        let backToFeed = app.buttons["scan-recording-back"]
        XCTAssertTrue(backToFeed.waitForExistence(timeout: 10))
        backToFeed.tap()

        let uploadOverlay = app.buttons["upload-overlay-compact"]
        XCTAssertTrue(uploadOverlay.waitForExistence(timeout: 10))
    }

    @MainActor
    func testWalletScenarioShowsAlphaPayoutGate() throws {
        let app = configuredApp(scenario: "wallet")
        app.launch()

        XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Set up identity and payouts"].waitForExistence(timeout: 10))
    }

    private func configuredApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BLUEPRINT_UI_TEST_MODE"] = "1"
        app.launchEnvironment["BLUEPRINT_UI_TEST_SCENARIO"] = scenario
        return app
    }
}
