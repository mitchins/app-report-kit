import XCTest
@testable import AppReportKit
@testable import AppReportKitUI
import SwiftUI

private let reportEndpointURL = URL(string: TestURLFactory.reportEndpoint)!

@MainActor
final class FeedbackFormModelTests: XCTestCase {
    func testValidationBlocksEmptyNotesSubmission() async throws {
        let transport = MockTransport()
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .bug,
            copy: .standard,
            screenContext: "InvoiceEditor"
        )

        await model.submit()

        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.standard.validationErrorMessage)
        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testSuccessfulSubmissionClearsNotesAndMarksSubmitted() async throws {
        let transport = MockTransport()
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .feature,
            copy: .standard,
            screenContext: "Settings"
        )
        model.notes = "Please add batch export."
        model.email = "user@example.com"

        await model.submit()

        XCTAssertTrue(model.isSubmitted)
        XCTAssertEqual(model.notes, "")
        XCTAssertEqual(model.email, "")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(transport.sendCallCount, 1)
    }

    func testDefaultCopyExists() {
        XCTAssertFalse(FeedbackFormCopy.standard.notesLabel.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.notesPlaceholder.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.standard.submitButtonTitle.isEmpty)
    }

    func testCustomCopyCanSupplyNotesLabelPlaceholderAndValidationMessage() async throws {
        let transport = MockTransport()
        let copy = FeedbackFormCopy {
            $0.notesLabel = "What should we know?"
            $0.notesPlaceholder = "Tell us the steps, bug, or request."
            $0.validationErrorMessage = "Please enter details before sending."
        }
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .bug,
            copy: copy,
            screenContext: "InvoiceEditor"
        )

        XCTAssertEqual(copy.notesLabel, "What should we know?")
        XCTAssertEqual(copy.notesPlaceholder, "Tell us the steps, bug, or request.")

        await model.submit()

        XCTAssertEqual(model.errorMessage, "Please enter details before sending.")
        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testFeedbackFormBodyCoversSeverityScreenContextAndStyleBranches() {
        let transport = MockTransport()
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .feature,
            copy: .standard,
            screenContext: "Composer"
        )
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
        let transport = MockTransport()
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .bug,
            copy: .standard,
            screenContext: nil
        )

        let form = FeedbackForm(
            model: model,
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
                        clientVersion: "0.1.0"
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

private enum TestURLFactory {
    static let reportEndpoint = "https://reports.example.com/v1/report"
}
