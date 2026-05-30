import XCTest
@testable import AppReportKit
@testable import AppReportKitUI

@MainActor
final class FeedbackFormModelTests: XCTestCase {
    func testValidationBlocksEmptyNotesSubmission() async throws {
        let transport = MockTransport()
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .bug,
            copy: .default,
            screenContext: "InvoiceEditor"
        )

        await model.submit()

        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(model.errorMessage, FeedbackFormCopy.default.validationErrorMessage)
        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testSuccessfulSubmissionClearsNotesAndMarksSubmitted() async throws {
        let transport = MockTransport()
        let model = FeedbackFormViewModel(
            client: makeClient(transport: transport),
            initialKind: .feature,
            copy: .default,
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
        XCTAssertFalse(FeedbackFormCopy.default.notesLabel.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.default.notesPlaceholder.isEmpty)
        XCTAssertFalse(FeedbackFormCopy.default.submitButtonTitle.isEmpty)
    }

    func testCustomCopyCanSupplyNotesLabelPlaceholderAndValidationMessage() async throws {
        let transport = MockTransport()
        let copy = FeedbackFormCopy(
            notesLabel: "What should we know?",
            notesPlaceholder: "Tell us the steps, bug, or request.",
            validationErrorMessage: "Please enter details before sending."
        )
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

    private func makeClient(transport: MockTransport) -> AppReportClient {
        AppReportClient(
            endpointURL: URL(string: "https://reports.example.com/v1/report")!,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            metadataProvider: FixedMetadataProvider(
                metadata: FeedbackMetadata(
                    appVersion: "1.2.3",
                    build: "42",
                    osName: "iOS",
                    osVersion: "18.5",
                    deviceModel: "iPhone16,2",
                    locale: "en-AU",
                    clientVersion: "0.1.0"
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
            appVersion: metadata.appVersion,
            build: metadata.build,
            osName: metadata.osName,
            osVersion: metadata.osVersion,
            deviceModel: metadata.deviceModel,
            locale: metadata.locale,
            clientVersion: metadata.clientVersion,
            screen: screen
        )
    }
}

private final class MockTransport: AppReportTransport {
    var sendCallCount = 0

    func send(request: URLRequest, body: Data) async throws -> AppReportTransportResponse {
        sendCallCount += 1
        return AppReportTransportResponse(statusCode: 202, data: Data(#"{"ok":true}"#.utf8))
    }
}
