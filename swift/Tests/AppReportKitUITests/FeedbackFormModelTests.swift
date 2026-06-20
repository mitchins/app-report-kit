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
        XCTAssertFalse(FeedbackFormCopy.standard.emailSubmitButtonTitle.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.shareSubmitButtonTitle.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.exportSubmitButtonTitle.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.submitButtonDisabledTitle.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.includeTechnicalDetailsLabel.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.includeTechnicalDetailsFootnote.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.submissionConfirmationTitle.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.includeScreenshotLabel.isEmpty)
        XCTAssertEqual(FeedbackFormCopy.standard.exportSubmitButtonDisabledTitle, "Add notes to export")
        XCTAssertEqual(FeedbackFormCopy.standard.unavailableSubmitButtonDisabledTitle, "Add notes to export")
    }

    func testSubmitButtonTextReflectsSubmissionRoute() {
        let emailSubmitter = MockFeedbackSubmitter(route: .email)
        let emailModel = makeModel(submitter: emailSubmitter)

        XCTAssertEqual(emailModel.submitButtonTitle, FeedbackFormCopy.standard.emailSubmitButtonDisabledTitle)

        emailModel.notes = "User report"
        XCTAssertEqual(emailModel.submitButtonTitle, FeedbackFormCopy.standard.emailSubmitButtonTitle)
        emailModel.notes = ""
        XCTAssertEqual(emailModel.submitButtonTitle, FeedbackFormCopy.standard.emailSubmitButtonDisabledTitle)

        let shareSubmitter = MockFeedbackSubmitter(route: .share)
        let shareModel = makeModel(submitter: shareSubmitter)
        XCTAssertEqual(shareModel.submitButtonTitle, FeedbackFormCopy.standard.shareSubmitButtonDisabledTitle)
        shareModel.notes = "User report"
        XCTAssertEqual(shareModel.submitButtonTitle, FeedbackFormCopy.standard.shareSubmitButtonTitle)
        shareModel.notes = ""
        XCTAssertEqual(shareModel.submitButtonTitle, FeedbackFormCopy.standard.shareSubmitButtonDisabledTitle)

        let exportSubmitter = MockFeedbackSubmitter(route: .export)
        let exportModel = makeModel(submitter: exportSubmitter)
        XCTAssertEqual(exportModel.submitButtonTitle, FeedbackFormCopy.standard.exportSubmitButtonDisabledTitle)
        exportModel.notes = "Export feedback"
        XCTAssertEqual(exportModel.submitButtonTitle, FeedbackFormCopy.standard.exportSubmitButtonTitle)
        exportModel.notes = ""
        XCTAssertEqual(exportModel.submitButtonTitle, FeedbackFormCopy.standard.exportSubmitButtonDisabledTitle)

        let unavailableSubmitter = MockFeedbackSubmitter(route: .unavailable)
        let unavailableModel = makeModel(submitter: unavailableSubmitter)
        XCTAssertEqual(unavailableModel.submitButtonTitle, FeedbackFormCopy.standard.unavailableSubmitButtonDisabledTitle)
        unavailableModel.notes = "Export feedback"
        XCTAssertEqual(unavailableModel.submitButtonTitle, FeedbackFormCopy.standard.unavailableSubmitButtonTitle)
        unavailableModel.notes = ""
        XCTAssertEqual(unavailableModel.submitButtonTitle, FeedbackFormCopy.standard.unavailableSubmitButtonDisabledTitle)
    }

    func testEmailFieldHiddenForEmailRouteEvenWhenPolicyAllowsEmail() {
        let submitter = MockFeedbackSubmitter(route: .email)
        let model = makeModel(
            submitter: submitter,
            policy: FeedbackFormPolicy(
                .init(
                    emailOptions: .init(
                        allowsEmail: true,
                        requiresEmail: false
                    )
                )
            )
        )

        XCTAssertFalse(model.showsEmailField)
    }

    func testEmailFieldVisibleWhenNotEmailRouteAndPolicyAllowsEmail() {
        let submitter = MockFeedbackSubmitter(route: .endpoint)
        let model = makeModel(
            submitter: submitter,
            policy: FeedbackFormPolicy(
                .init(
                    emailOptions: .init(
                        allowsEmail: true,
                        requiresEmail: false
                    )
                )
            )
        )

        XCTAssertTrue(model.showsEmailField)
    }

    func testEmailRouteCanSubmitWithoutEmailWhenPolicyRequiresEmail() async throws {
        let submitter = MockFeedbackSubmitter(route: .email)
        let model = makeModel(
            submitter: submitter,
            policy: FeedbackFormPolicy(
                .init(
                    emailOptions: .init(
                        allowsEmail: true,
                        requiresEmail: true
                    )
                )
            )
        )

        model.notes = "Could not export report."

        await model.submit()

        XCTAssertEqual(submitter.requests.count, 1)
        XCTAssertNil(submitter.requests.last?.email)
        XCTAssertNil(model.errorMessage)
    }

    func testEmailRouteUsesRouteAwarePolicyInFormInit() {
        let form = FeedbackForm(
            submitter: MockFeedbackSubmitter(route: .email),
            policy: FeedbackFormPolicy(
                .init(
                    emailOptions: .init(
                        allowsEmail: true,
                        requiresEmail: false
                    )
                )
            )
        )

        _ = form.body
    }

    func testScreenshotPreviewStateControlsSubmissionPayload() async throws {
        let submitter = MockFeedbackSubmitter(
            supportOptions: .init(
                allowsScreenshot: true,
                screenshotEnabledByDefault: true
            ),
            screenshots: [
                FeedbackScreenshot(
                    data: Data("png".utf8),
                    filename: "screenshot.png",
                    contentType: "image/png",
                )
            ]
        )
        let model = makeModel(
            submitter: submitter,
            supportOptions: submitter.feedbackFormSupportOptions,
            policy: .clientDebug
        )

        model.notes = "Looks blurry"
        await model.submit()

        XCTAssertEqual(submitter.requests.last?.includeScreenshot, true)

        model.notes = "Need more evidence"
        model.removeAllScreenshots()
        model.includeScreenshot = true
        await model.submit()

        XCTAssertEqual(submitter.requests.last?.includeScreenshot, false)
    }

    func testRemovingOneScreenshotOnlySendsTheRemainingAttachment() async throws {
        let submitter = MockFeedbackSubmitter(
            supportOptions: .init(
                allowsScreenshot: true,
                screenshotEnabledByDefault: true
            ),
            screenshots: [
                FeedbackScreenshot(
                    data: Data("first".utf8),
                    filename: "first.png",
                    contentType: "image/png",
                ),
                FeedbackScreenshot(
                    data: Data("second".utf8),
                    filename: "second.png",
                    contentType: "image/png"
                )
            ]
        )
        let model = makeModel(
            submitter: submitter,
            supportOptions: submitter.feedbackFormSupportOptions,
            policy: .clientDebug
        )

        model.notes = "Need more evidence"
        model.removeScreenshot(model.screenshotPreviews[0].id)

        await model.submit()

        let request = try XCTUnwrap(submitter.requests.last)
        XCTAssertTrue(request.includeScreenshot)
        XCTAssertEqual(request.screenshotAttachments.map(\.filename), ["second.png"])
    }

    func testSimpleIssuePolicyHidesKindPickerAndSeverityPicker() {
        let model = makeModel(
            submitter: MockFeedbackSubmitter(),
            policy: .simpleIssue,
            initialKind: .feedback
        )

        XCTAssertFalse(model.showsKindPicker)
        XCTAssertFalse(model.showsSeverityPicker)
        XCTAssertEqual(model.kind, .bug)
    }

    func testNotesAreRequiredByDefaultAndCanSubmitWhenProvided() async throws {
        let submitter = MockFeedbackSubmitter()
        let model = makeModel(submitter: submitter)

        await model.submit()

        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.validationErrorMessage)
        XCTAssertEqual(submitter.requests.count, 0)

        model.notes = "Could not export report."
        await model.submit()
        XCTAssertEqual(submitter.requests.count, 1)
    }

    func testEmailIsOptionalByDefault() async throws {
        let submitter = MockFeedbackSubmitter()
        let model = makeModel(submitter: submitter)
        model.notes = "Could not export report."

        await model.submit()

        let request = try XCTUnwrap(submitter.requests.last)
        XCTAssertNil(request.email)
    }

    func testEmailCanBeRequiredByPolicy() async throws {
        let submitter = MockFeedbackSubmitter()
        let model = makeModel(
            submitter: submitter,
            policy: FeedbackFormPolicy(
                .init(
                    emailOptions: .init(
                        allowsEmail: true,
                        requiresEmail: true
                    )
                )
            )
        )

        model.notes = "Could not export report."
        await model.submit()
        XCTAssertEqual(submitter.requests.count, 0)
        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.validationErrorMessage)

        model.email = "user@example.com"
        await model.submit()
        XCTAssertEqual(submitter.requests.count, 1)
        XCTAssertEqual(submitter.requests.last?.email, "user@example.com")
    }

    func testCustomCopyOverridesStillWorkForCTAAndValidationMessage() async throws {
        let copy = FeedbackFormCopy {
            $0.notesLabel = "What’s the issue?"
            $0.notesPlaceholder = "Tell us what happened"
            $0.submitButtonDisabledTitle = "Add a short description"
            $0.shareSubmitButtonTitle = "Share report"
            $0.validationErrorMessage = "Please share what happened."
        }
        let model = makeModel(
            submitter: MockFeedbackSubmitter(route: .share),
            copy: copy
        )
        let emailModel = makeModel(
            submitter: MockFeedbackSubmitter(route: .email),
            copy: copy
        )

        XCTAssertEqual(model.submitButtonTitle, copy.shareSubmitButtonDisabledTitle)
        XCTAssertEqual(copy.notesLabel, "What’s the issue?")
        XCTAssertEqual(copy.notesPlaceholder, "Tell us what happened")
        model.notes = "App froze"
        XCTAssertEqual(model.submitButtonTitle, copy.shareSubmitButtonTitle)
        model.notes = ""
        await model.submit()
        XCTAssertEqual(model.errorMessage, copy.validationErrorMessage)

        emailModel.notes = "User report"
        XCTAssertEqual(emailModel.submitButtonTitle, copy.emailSubmitButtonTitle)
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
            submitter: MockFeedbackSubmitter(
                supportOptions: .init(
                    allowsTechnicalDetails: true,
                    allowsScreenshot: true,
                    technicalDetailsEnabledByDefault: true,
                    screenshotEnabledByDefault: true
                ),
                screenshots: [
                    FeedbackScreenshot(
                        data: Data("png".utf8),
                        filename: "screenshot.png",
                        contentType: "image/png"
                    )
                ]
            ),
            supportOptions: FeedbackFormSupportOptions(
                allowsTechnicalDetails: true,
                allowsScreenshot: true,
                technicalDetailsEnabledByDefault: true,
                screenshotEnabledByDefault: true
            ),
            policy: .clientDebug
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
            ),
            screenshots: [
                FeedbackScreenshot(
                    data: Data("png".utf8),
                    filename: "screenshot.png",
                    contentType: "image/png"
                )
            ]
        )
        let model = makeModel(
            submitter: submitter,
            supportOptions: submitter.feedbackFormSupportOptions,
            policy: .clientDebug
        )
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
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)

        let submitter = MockFeedbackSubmitter(
            outcome: .needsUserAction(
                .share(
                    FeedbackPendingShare(
                        subject: "JustCards Report",
                        message: "Share this bundle",
                        itemURLs: [URL(fileURLWithPath: "/tmp/AppReportDiagnostics.bundle")],
                        temporaryDirectoryURL: temporaryDirectoryURL
                    )
                )
            )
        )
        let model = makeModel(submitter: submitter)
        model.notes = "Need help"

        await model.submit()

        XCTAssertFalse(model.isSubmitted)
        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.submissionErrorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectoryURL.path))
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

    func testLogsConfirmationCanResubmitWithoutLogs() async throws {
        let submitter = MockFeedbackSubmitter(
            outcomes: [
                .needsConfirmation(
                    FeedbackSubmissionConfirmation(
                        unsupported: [.files],
                        alternateDelivery: .email(
                            FeedbackPendingEmail(
                                recipients: ["support@example.com"],
                                subject: "JustCards Report",
                                body: "Email logs",
                                attachments: []
                            )
                        )
                    )
                ),
                .submitted(
                    AppReportSubmissionResponse(accepted: true, statusCode: 202)
                )
            ],
            supportOptions: FeedbackFormSupportOptions(
                allowsTechnicalDetails: true
            )
        )
        let model = makeModel(
            submitter: submitter,
            supportOptions: submitter.feedbackFormSupportOptions,
            policy: .clientDebug
        )
        model.notes = "Need help"

        await model.submit()

        XCTAssertTrue(model.showsSubmissionConfirmation)
        XCTAssertEqual(submitter.requests.count, 1)
        XCTAssertTrue(submitter.requests[0].includeTechnicalDetails)

        model.sendWithoutUnsupportedPayloads()
        await model.confirmationActionTask?.value

        XCTAssertFalse(model.showsSubmissionConfirmation)
        XCTAssertTrue(model.isSubmitted)
        XCTAssertEqual(submitter.requests.count, 2)
        XCTAssertFalse(submitter.requests[1].includeTechnicalDetails)
    }

    func testLogsConfirmationCanUseAlternateDelivery() async throws {
        let pendingDelivery = FeedbackPendingDelivery.email(
            FeedbackPendingEmail(
                recipients: ["support@example.com"],
                subject: "JustCards Report",
                body: "Email logs",
                attachments: []
            )
        )
        let submitter = MockFeedbackSubmitter(
            outcome: .needsConfirmation(
                FeedbackSubmissionConfirmation(
                    unsupported: [.files],
                    alternateDelivery: pendingDelivery
                )
            ),
            supportOptions: FeedbackFormSupportOptions(
                allowsTechnicalDetails: true
            )
        )
        var handledDeliveries: [FeedbackPendingDelivery] = []
        let model = makeModel(
            submitter: submitter,
            supportOptions: submitter.feedbackFormSupportOptions,
            policy: .clientDebug,
            deliveryHandler: { delivery in
                handledDeliveries.append(delivery)
                return true
            }
        )
        model.notes = "Need help"

        await model.submit()
        model.sendUsingAlternateDelivery()
        await model.confirmationActionTask?.value

        XCTAssertEqual(handledDeliveries, [pendingDelivery])
        XCTAssertTrue(model.isSubmitted)
        XCTAssertFalse(model.showsSubmissionConfirmation)
    }

    func testLogsConfirmationWithoutHandlerShowsErrorForAlternateDelivery() async throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)

        let submitter = MockFeedbackSubmitter(
            outcome: .needsConfirmation(
                FeedbackSubmissionConfirmation(
                    unsupported: [.images],
                    alternateDelivery: .share(
                        FeedbackPendingShare(
                            subject: "JustCards Report",
                            message: "Share logs",
                            itemURLs: [],
                            temporaryDirectoryURL: temporaryDirectoryURL
                        )
                    )
                )
            ),
            supportOptions: FeedbackFormSupportOptions(
                allowsTechnicalDetails: true
            )
        )
        let model = makeModel(
            submitter: submitter,
            supportOptions: submitter.feedbackFormSupportOptions,
            policy: .clientDebug
        )
        model.notes = "Need help"

        await model.submit()
        model.sendUsingAlternateDelivery()
        await model.confirmationActionTask?.value

        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.submissionErrorMessage)
        XCTAssertFalse(model.isSubmitted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectoryURL.path))
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
        policy: FeedbackFormPolicy = .standard,
        initialKind: FeedbackReportKind = .bug,
        deliveryHandler: FeedbackDeliveryHandler? = nil
    ) -> FeedbackFormViewModel {
        FeedbackFormViewModel(
            submitter: submitter,
            initialKind: initialKind,
            copy: copy,
            screenContext: "InvoiceEditor",
            supportOptions: supportOptions,
            policy: policy,
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

private final class MockFeedbackSubmitter: FeedbackSubmitting, FeedbackFormSupportProviding, FeedbackFormPolicyProviding {
    var requests: [FeedbackSubmissionRequest] = []
    let feedbackFormSupportOptions: FeedbackFormSupportOptions
    let feedbackSubmissionRoute: FeedbackSubmissionRoute
    let feedbackFormPolicy: FeedbackFormPolicy

    private let outcomes: [FeedbackSubmissionOutcome]
    private let screenshots: [FeedbackScreenshot]

    init(
        outcome: FeedbackSubmissionOutcome = .submitted(
            AppReportSubmissionResponse(accepted: true, statusCode: 202)
        ),
        outcomes: [FeedbackSubmissionOutcome]? = nil,
        supportOptions: FeedbackFormSupportOptions = .disabled,
        route: FeedbackSubmissionRoute = .endpoint,
        screenshots: [FeedbackScreenshot] = []
    ) {
        self.outcomes = outcomes ?? [outcome]
        feedbackFormSupportOptions = supportOptions
        feedbackSubmissionRoute = route
        self.screenshots = screenshots
        feedbackFormPolicy = .standard
    }

    func submit(_ request: FeedbackSubmissionRequest) async throws -> FeedbackSubmissionOutcome {
        requests.append(request)
        let index = min(requests.count - 1, outcomes.count - 1)
        return outcomes[index]
    }
}

extension MockFeedbackSubmitter: FeedbackSubmissionRouteProviding, FeedbackScreenshotProviding {
    func currentBreadcrumbs() async -> [FeedbackBreadcrumb] {
        []
    }

    func makeScreenshots() throws -> [FeedbackScreenshot] {
        screenshots
    }
}

private enum TestURLFactory {
    static let reportEndpoint = "https://reports.example.com/v1/report"
}
