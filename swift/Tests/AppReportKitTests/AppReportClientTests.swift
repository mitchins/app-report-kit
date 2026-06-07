import XCTest
@testable import AppReportKit

private let reportEndpointURL = URL(string: TestURLFactory.reportEndpoint)!
private let customEndpointURL = URL(string: TestURLFactory.customReportEndpoint)!

final class AppReportClientTests: XCTestCase {
    func testEncodesValidReportPayload() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        _ = try await client.submit(
            kind: .bug,
            notes: "Export fails from invoice editor",
            severity: .high,
            email: "user@example.com",
            screen: "InvoiceEditor",
            attachments: [
                FeedbackAttachment(
                    filename: "screenshot.png",
                    contentType: "image/png",
                    data: Data("png".utf8)
                )
            ]
        )

        let payload = try XCTUnwrap(transport.lastDecodedPayload())
        XCTAssertEqual(payload.appId, "justcards")
        XCTAssertEqual(payload.kind, .bug)
        XCTAssertEqual(payload.severity, .high)
        XCTAssertEqual(payload.notes, "Export fails from invoice editor")
        XCTAssertEqual(payload.email, "user@example.com")
        XCTAssertEqual(payload.metadata.screen, "InvoiceEditor")
        XCTAssertEqual(payload.attachments.count, 1)
    }

    func testRequiresNotesBeforeSubmit() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.submit(kind: .bug, notes: "   ")
            XCTFail("Expected empty notes to fail")
        } catch let error as AppReportClientError {
            XCTAssertEqual(error, .emptyNotes)
        }

        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testSupportsBugFeatureAndFeedbackKinds() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        for kind in FeedbackReportKind.allCases {
            _ = try await client.submit(kind: kind, notes: "Message for \(kind.rawValue)")
            let payload = try XCTUnwrap(transport.lastDecodedPayload())
            XCTAssertEqual(payload.kind, kind)
        }
    }

    func testIncludesAutomaticMetadataFromInjectedProvider() async throws {
        let transport = MockTransport()
        let metadataProvider = FixedMetadataProvider(
            metadata: FeedbackMetadata(
                app: .init(
                    version: "9.9.9",
                    build: "999",
                    clientVersion: "0.1.0-test",
                    screen: "Composer"
                ),
                device: .init(
                    osName: "iOS",
                    osVersion: "18.5",
                    model: "iPhone16,2",
                    locale: "en-AU"
                )
            )
        )
        let client = makeClient(transport: transport, metadataProvider: metadataProvider)

        _ = try await client.submit(kind: .feedback, notes: "Nice app", screen: "Composer")

        let payload = try XCTUnwrap(transport.lastDecodedPayload())
        XCTAssertEqual(payload.metadata.appVersion, "9.9.9")
        XCTAssertEqual(payload.metadata.build, "999")
        XCTAssertEqual(payload.metadata.clientVersion, "0.1.0-test")
        XCTAssertEqual(payload.metadata.screen, "Composer")
    }

    func testOmitsEmailWhenEmpty() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        _ = try await client.submit(kind: .feature, notes: "Please add sorting", email: "  ")

        let json = try XCTUnwrap(String(data: transport.lastBody ?? Data(), encoding: .utf8))
        XCTAssertFalse(json.contains("\"email\""))
    }

    func testSendsBearerTokenAndInjectableEndpoint() async throws {
        let transport = MockTransport()
        let client = makeClient(
            endpointURL: customEndpointURL,
            transport: transport
        )

        _ = try await client.submit(kind: .bug, notes: "A report")

        XCTAssertEqual(transport.lastRequest?.url?.absoluteString, TestURLFactory.customReportEndpoint)
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer TEST_APP_REPORT_KEY")
    }

    func testUsesInjectedTransport() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        _ = try await client.submit(kind: .feedback, notes: "A report")

        XCTAssertEqual(transport.sendCallCount, 1)
    }

    func testSubmitMapsSuccessResponse() async throws {
        let transport = MockTransport(statusCode: 202)
        let client = makeClient(transport: transport)

        let response = try await client.submit(kind: .bug, notes: "A report")

        XCTAssertEqual(response, AppReportSubmissionResponse(accepted: true, statusCode: 202))
    }

    func testSubmitMapsFailureResponse() async throws {
        let transport = MockTransport(statusCode: 429)
        let client = makeClient(transport: transport)

        do {
            _ = try await client.submit(kind: .bug, notes: "A report")
            XCTFail("Expected failure response")
        } catch let error as AppReportClientError {
            XCTAssertEqual(error, .serverRejected(statusCode: 429))
        }
    }

    func testSubmissionProtocolOmitsInjectedDiagnosticsWhenToggleIsOff() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        let outcome = try await client.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "No extra details",
                options: .init(includeTechnicalDetails: false)
            )
        )

        guard case .submitted = outcome else {
            return XCTFail("Expected direct submission")
        }

        let payload = try XCTUnwrap(transport.lastDecodedPayload())
        XCTAssertNil(payload.diagnostics)
    }

    func testSubmissionProtocolIncludesInjectedDiagnosticsWhenToggleIsOn() async throws {
        let transport = MockTransport()
        let client = makeClient(transport: transport)

        let outcome = try await client.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Need details",
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case .submitted = outcome else {
            return XCTFail("Expected direct submission")
        }

        let payload = try XCTUnwrap(transport.lastDecodedPayload())
        XCTAssertEqual(payload.diagnostics?["lastAction"], "Tapped Export")
    }

    private func makeClient(
        endpointURL: URL = reportEndpointURL,
        transport: MockTransport,
        metadataProvider: FeedbackMetadataProviding = FixedMetadataProvider.standard
    ) -> AppReportClient {
        AppReportClient(
            endpointURL: endpointURL,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            diagnosticsProvider: FixedDiagnosticsProvider(),
            metadataProvider: metadataProvider,
            transport: transport
        )
    }
}

private struct FixedDiagnosticsProvider: FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String] {
        ["lastAction": "Tapped Export"]
    }
}

private struct FixedMetadataProvider: FeedbackMetadataProviding {
    let metadata: FeedbackMetadata

    static let standard = FixedMetadataProvider(
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
    )

    func makeMetadata(screen: String?) -> FeedbackMetadata {
        FeedbackMetadata(
            app: .init(
                version: metadata.appVersion,
                build: metadata.build,
                clientVersion: metadata.clientVersion,
                screen: screen ?? metadata.screen
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
    private let statusCode: Int

    var sendCallCount = 0
    var lastRequest: URLRequest?
    var lastBody: Data?

    init(statusCode: Int = 202) {
        self.statusCode = statusCode
    }

    func send(request: URLRequest, body: Data) async throws -> AppReportTransportResponse {
        sendCallCount += 1
        lastRequest = request
        lastBody = body
        return AppReportTransportResponse(statusCode: statusCode, data: Data(#"{"ok":true}"#.utf8))
    }

    func lastDecodedPayload() throws -> FeedbackReport? {
        guard let lastBody else {
            return nil
        }

        return try JSONDecoder().decode(FeedbackReport.self, from: lastBody)
    }
}

private enum TestURLFactory {
    static let reportEndpoint = "https://reports.example.com/v1/report"
    static let customReportEndpoint = "https://reports.example.com/custom"
}
