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

        let skipInvite = app.buttons["Skip for now"]
        XCTAssertTrue(skipInvite.waitForExistence(timeout: 10))
        skipInvite.tap()

        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Create Account"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["you@example.com"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCorePathScenarioStartsCaptureAndShowsUploadOverlay() throws {
        let app = configuredApp(scenario: "corePath")
        app.launch()

        let firstFeatured = app.buttons["scan-home-featured-0"]
        XCTAssertTrue(firstFeatured.waitForExistence(timeout: 10))
        firstFeatured.tap()

        let primaryAction = app.buttons["job-detail-primary-action"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 10))
        primaryAction.tap()

        let stopButton = app.buttons["scan-recording-stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        stopButton.tap()

        let uploadOverlay = app.buttons["upload-overlay-compact"]
        XCTAssertTrue(uploadOverlay.waitForExistence(timeout: 10))
    }

    @MainActor
    func testWalletScenarioShowsAlphaPayoutGate() throws {
        let app = configuredApp(scenario: "wallet")
        app.launch()

        XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Payout setup unavailable"].waitForExistence(timeout: 10))
    }

    private func configuredApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BLUEPRINT_UI_TEST_MODE"] = "1"
        app.launchEnvironment["BLUEPRINT_UI_TEST_SCENARIO"] = scenario
        return app
    }
}
