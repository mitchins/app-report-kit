import XCTest
@testable import AppReportKit
@testable import AppReportKitUI
import SwiftUI

private let reportEndpointURL = URL(string: TestURLFactory.reportEndpoint)!

@MainActor
final class FeedbackFormModelTests: XCTestCase {
    func testValidationBlocksEmptyNotesSubmission() async throws {
        let submitter = MockFeedbackSubmitter()
        let model = makeModel(submitter: submitter)

        await model.submit()

        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.validationErrorMessage)
        XCTAssertEqual(submitter.requests.count, 0)
    }

    func testSuccessfulSubmissionClearsNotesAndMarksSubmitted() async throws {
        let submitter = MockFeedbackSubmitter()
        let model = makeModel(submitter: submitter)
        model.notes = "Please add batch export."
        model.email = "user@example.com"

        await model.submit()

        XCTAssertTrue(model.isSubmitted)
        XCTAssertEqual(model.notes, "")
        XCTAssertEqual(model.email, "")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(submitter.requests.count, 1)
    }

    func testDefaultCopyExists() {
        XCTAssertFalse(FeedbackFormCopy.standard.notesLabel.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.notesPlaceholder.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.submitButtonTitle.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.includeTechnicalDetailsLabel.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.includeScreenshotLabel.isEmpty)
    }

    func testCustomCopyCanSupplyNotesLabelPlaceholderAndValidationMessage() async throws {
        let submitter = MockFeedbackSubmitter()
        let copy = FeedbackFormCopy {
            $0.notesLabel = "What should we know?"
            $0.notesPlaceholder = "Tell us the steps, bug, or request."
            $0.validationErrorMessage = "Please enter details before sending."
        }
        let model = makeModel(submitter: submitter, copy: copy)

        XCTAssertEqual(copy.notesLabel, "What should we know?")
        XCTAssertEqual(copy.notesPlaceholder, "Tell us the steps, bug, or request.")

        await model.submit()

        XCTAssertEqual(model.errorMessage, "Please enter details before sending.")
        XCTAssertEqual(submitter.requests.count, 0)
    }

    func testControlsStayHiddenWhenSupportOptionsAreDisabled() {
        let model = makeModel(submitter: MockFeedbackSubmitter())

        XCTAssertFalse(model.showsTechnicalDetailsToggle)
        XCTAssertFalse(model.showsScreenshotToggle)
    }

    func testConfiguredSupportOptionsShowTogglesAndUseDefaults() {
        let model = makeModel(
            submitter: MockFeedbackSubmitter(),
            supportOptions: FeedbackFormSupportOptions(
                allowsTechnicalDetails: true,
                allowsScreenshot: true,
                technicalDetailsEnabledByDefault: true,
                screenshotEnabledByDefault: true
            )
        )

        XCTAssertTrue(model.showsTechnicalDetailsToggle)
        XCTAssertTrue(model.showsScreenshotToggle)
        XCTAssertTrue(model.includeTechnicalDetails)
        XCTAssertTrue(model.includeScreenshot)
    }

    func testToggleOffDoesNotRequestTechnicalDetailsOrScreenshot() async throws {
        let submitter = MockFeedbackSubmitter(
            supportOptions: FeedbackFormSupportOptions(
                allowsTechnicalDetails: true,
                allowsScreenshot: true
            )
        )
        let model = makeModel(submitter: submitter, supportOptions: submitter.feedbackFormSupportOptions)
        model.notes = "Still repros"
        model.includeTechnicalDetails = false
        model.includeScreenshot = false

        await model.submit()

        let request = try XCTUnwrap(submitter.requests.first)
        XCTAssertFalse(request.includeTechnicalDetails)
        XCTAssertFalse(request.includeScreenshot)
    }

    func testPendingDeliveryRequiresHandlerToCompleteSubmission() async throws {
        let pendingDelivery = FeedbackPendingDelivery.share(
            FeedbackPendingShare(
                subject: "JustCards Report",
                message: "Share this bundle",
                itemURLs: [URL(fileURLWithPath: "/tmp/AppReportDiagnostics.bundle")]
            )
        )
        let submitter = MockFeedbackSubmitter(outcome: .needsUserAction(pendingDelivery))
        var handledDeliveries: [FeedbackPendingDelivery] = []
        let model = makeModel(
            submitter: submitter,
            deliveryHandler: { delivery in
                handledDeliveries.append(delivery)
                return true
            }
        )
        model.notes = "Need help"

        await model.submit()

        XCTAssertEqual(handledDeliveries, [pendingDelivery])
        XCTAssertTrue(model.isSubmitted)
    }

    func testPendingDeliveryWithoutHandlerShowsError() async throws {
        let submitter = MockFeedbackSubmitter(
            outcome: .needsUserAction(
                .share(
                    FeedbackPendingShare(
                        subject: "JustCards Report",
                        message: "Share this bundle",
                        itemURLs: [URL(fileURLWithPath: "/tmp/AppReportDiagnostics.bundle")]
                    )
                )
            )
        )
        let model = makeModel(submitter: submitter)
        model.notes = "Need help"

        await model.submit()

        XCTAssertFalse(model.isSubmitted)
        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.submissionErrorMessage)
    }

    func testPendingDeliveryHandlerReturningFalseKeepsFormState() async throws {
        let submitter = MockFeedbackSubmitter(
            outcome: .needsUserAction(
                .share(
                    FeedbackPendingShare(
                        subject: "JustCards Report",
                        message: "Share this bundle",
                        itemURLs: [URL(fileURLWithPath: "/tmp/AppReportDiagnostics.bundle")]
                    )
                )
            )
        )
        let model = makeModel(
            submitter: submitter,
            deliveryHandler: { _ in false }
        )
        model.notes = "Need help"
        model.email = "person@example.com"

        await model.submit()

        XCTAssertFalse(model.isSubmitted)
        XCTAssertEqual(model.notes, "Need help")
        XCTAssertEqual(model.email, "person@example.com")
    }

    func testFeedbackFormClientInitializerStillBuildsWithoutDiagnostics() {
        let transport = MockTransport()
        let form = FeedbackForm(
            client: makeClient(transport: transport),
            screenContext: "Composer"
        )

        _ = form.body
    }

    func testFeedbackFormBodyCoversSeverityScreenContextAndStyleBranches() {
        let model = makeModel(submitter: MockFeedbackSubmitter())
        model.notes = "Need an export button."
        model.email = "person@example.com"

        let styledForm = FeedbackForm(
            model: model,
            copy: .standard,
            style: FeedbackFormStyle(
                foregroundColor: .primary,
                backgroundColor: .secondary,
                accentColor: .accentColor,
                font: .body
            ),
            showsSeverityPicker: false,
            screenContext: "Composer"
        )

        _ = styledForm.body

        model.isSubmitting = true
        _ = styledForm.body

        model.isSubmitting = false
        model.isSubmitted = true
        _ = styledForm.body

        model.isSubmitted = false
        model.errorMessage = "Unable to send right now."
        _ = styledForm.body
    }

    func testFeedbackFormBodyCoversEmptyNotesPlaceholderBranch() {
        let form = FeedbackForm(
            model: makeModel(submitter: MockFeedbackSubmitter()),
            copy: .standard,
            style: .standard,
            showsSeverityPicker: true,
            screenContext: nil
        )

        _ = form.body
    }

    func testFeedbackFormStyleStandardAndCustomValues() {
        let standard = FeedbackFormStyle.standard
        XCTAssertNil(standard.foregroundColor)
        XCTAssertNil(standard.backgroundColor)
        XCTAssertNil(standard.accentColor)
        XCTAssertNil(standard.font)

        let custom = FeedbackFormStyle(
            foregroundColor: .primary,
            backgroundColor: .secondary,
            accentColor: .accentColor,
            font: .headline
        )

        XCTAssertNotNil(custom.foregroundColor)
        XCTAssertNotNil(custom.backgroundColor)
        XCTAssertNotNil(custom.accentColor)
        XCTAssertNotNil(custom.font)
    }

    private func makeModel(
        submitter: any FeedbackSubmitting,
        copy: FeedbackFormCopy = .standard,
        supportOptions: FeedbackFormSupportOptions = .disabled,
        deliveryHandler: FeedbackDeliveryHandler? = nil
    ) -> FeedbackFormViewModel {
        FeedbackFormViewModel(
            submitter: submitter,
            initialKind: .bug,
            copy: copy,
            screenContext: "InvoiceEditor",
            supportOptions: supportOptions,
            deliveryHandler: deliveryHandler
        )
    }

    private func makeClient(transport: MockTransport) -> AppReportClient {
        AppReportClient(
            endpointURL: reportEndpointURL,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            metadataProvider: FixedMetadataProvider(
                metadata: FeedbackMetadata(
                    app: .init(
                        version: "1.2.3",
                        build: "42",
                        clientVersion: "0.2.0"
                    ),
                    device: .init(
                        osName: "iOS",
                        osVersion: "18.5",
                        model: "iPhone16,2",
                        locale: "en-AU"
                    )
                )
            ),
            transport: transport
        )
    }
}

private struct FixedMetadataProvider: FeedbackMetadataProviding {
    let metadata: FeedbackMetadata

    func makeMetadata(screen: String?) -> FeedbackMetadata {
        FeedbackMetadata(
            app: .init(
                version: metadata.appVersion,
                build: metadata.build,
                clientVersion: metadata.clientVersion,
                screen: screen
            ),
            device: .init(
                osName: metadata.osName,
                osVersion: metadata.osVersion,
                model: metadata.deviceModel,
                locale: metadata.locale
            )
        )
    }
}

private final class MockTransport: AppReportTransport {
    var sendCallCount = 0

    func send(request _: URLRequest, body _: Data) async throws -> AppReportTransportResponse {
        sendCallCount += 1
        return AppReportTransportResponse(statusCode: 202, data: Data(#"{"ok":true}"#.utf8))
    }
}

private final class MockFeedbackSubmitter: FeedbackSubmitting, FeedbackFormSupportProviding {
    var requests: [FeedbackSubmissionRequest] = []
    let feedbackFormSupportOptions: FeedbackFormSupportOptions

    private let outcome: FeedbackSubmissionOutcome

    init(
        outcome: FeedbackSubmissionOutcome = .submitted(
            AppReportSubmissionResponse(accepted: true, statusCode: 202)
        ),
        supportOptions: FeedbackFormSupportOptions = .disabled
    ) {
        self.outcome = outcome
        feedbackFormSupportOptions = supportOptions
    }

    func submit(_ request: FeedbackSubmissionRequest) async throws -> FeedbackSubmissionOutcome {
        requests.append(request)
        return outcome
    }
}

private enum TestURLFactory {
    static let reportEndpoint = "https://reports.example.com/v1/report"
}
