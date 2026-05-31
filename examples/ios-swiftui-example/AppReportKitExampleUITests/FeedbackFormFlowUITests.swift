import XCTest

final class FeedbackFormFlowUITests: XCTestCase {
    private let snapshotDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppReportKitExampleSnapshots", isDirectory: true)

    /// Captures a clean initial-state screenshot for documentation before any interaction.
    func testFormSnapshotForDocumentation() throws {
        let app = launchApp()

        // Wait for the form to fully render
        XCTAssertTrue(app.buttons["appreportkit.kind-picker"].waitForExistence(timeout: 5))
        // Give layout a moment to settle after the navigation bar animates in
        Thread.sleep(forTimeInterval: 0.8)

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "feedback-form-iPhone17Pro"
        attachment.lifetime = .keepAlways
        add(attachment)

        let outputURL = try saveSnapshot(screenshot, fileName: "feedback-form-iPhone17Pro.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testEmptyFormKeepsSubmitDisabled() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["appreportkit.kind-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appreportkit.severity-picker"].exists)
        XCTAssertTrue(app.staticTexts["appreportkit.context-value"].exists)
        XCTAssertTrue(app.textViews["appreportkit.notes-editor"].exists)

        let form = app.scrollViews.firstMatch
        if form.exists {
            form.swipeUp()
        } else {
            app.swipeUp()
        }

        XCTAssertTrue(app.buttons["appreportkit.submit-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["appreportkit.submit-button"].isEnabled)
    }

    func testSubmittingValidReportShowsSuccess() {
        let app = launchApp()

        let notes = app.textViews["appreportkit.notes-editor"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("Steps to reproduce:\n1. Open Invoice Editor\n2. Tap Export\n3. Nothing happens")

        let email = app.textFields["appreportkit.email-field"]
        XCTAssertTrue(email.exists)
        email.tap()
        email.typeText("person@example.com")

        // Dismiss keyboard before tapping submit so it's out of the way
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)

        let submit = app.buttons["appreportkit.submit-button"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        let success = app.staticTexts["appreportkit.success-message"]
        XCTAssertTrue(success.waitForExistence(timeout: 5))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-appreportkit-ui-testing"]
        app.launch()
        return app
    }

    private func saveSnapshot(_ screenshot: XCUIScreenshot, fileName: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: snapshotDirectory,
            withIntermediateDirectories: true
        )

        let url = snapshotDirectory.appendingPathComponent(fileName)
        try screenshot.pngRepresentation.write(to: url)
        return url
    }
}
