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

        let approvedTask = waitForApprovedTask(in: app)
        approvedTask.tap()

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

        let approvedTask = waitForApprovedTask(in: app)
        approvedTask.tap()

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
        XCTAssertTrue(app.staticTexts["Payout setup unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Payout setup requires backend-verified Stripe readiness. This build only shows wallet and review status."].waitForExistence(timeout: 10))
    }

    private func configuredApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BLUEPRINT_UI_TEST_MODE"] = "1"
        app.launchEnvironment["BLUEPRINT_UI_TEST_SCENARIO"] = scenario
        return app
    }

    private func waitForApprovedTask(in app: XCUIApplication) -> XCUIElement {
        let approvedTask = app.buttons["capturer-task-ui_test_job_approved"]
        if approvedTask.waitForExistence(timeout: 10) {
            return approvedTask
        }

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<4 where !approvedTask.exists {
            scrollView.swipeUp()
        }
        XCTAssertTrue(approvedTask.waitForExistence(timeout: 3))
        return approvedTask
    }
}
