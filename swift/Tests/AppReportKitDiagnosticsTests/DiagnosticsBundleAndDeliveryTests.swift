import Foundation
import XCTest
@testable import AppReportKit
@testable import AppReportKitDiagnostics

final class DiagnosticsBundleAndDeliveryTests: XCTestCase {
    func testBundleIncludesCoreFilesAndOptionalArtifactsAndCleansUp() throws {
        let builder = DiagnosticsBundleBuilder()
        let materialization = try builder.build(
            report: makeReport(),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [makeNetworkEvent()],
            screenshots: [
                DiagnosticsAttachment(
                    data: Data("png".utf8),
                    filename: "screenshot-1.png",
                    contentType: "image/png"
                )
            ]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: materialization.rootURL.appendingPathComponent("report.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: materialization.rootURL.appendingPathComponent("metadata.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: materialization.rootURL.appendingPathComponent("README.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: materialization.rootURL.appendingPathComponent("network.har").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: materialization.rootURL.appendingPathComponent("screenshots/screenshot-1.png").path))
        XCTAssertFalse(materialization.fileAttachments.isEmpty)

        try builder.cleanup(materialization)
        XCTAssertFalse(FileManager.default.fileExists(atPath: materialization.rootURL.path))
    }

    func testBundleIncludesDiagnosticsDictionaryInReportJSON() throws {
        let builder = DiagnosticsBundleBuilder()
        let materialization = try builder.build(
            report: makeReport(),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [],
            screenshots: []
        )
        defer {
            try? builder.cleanup(materialization)
        }

        let data = try Data(contentsOf: materialization.rootURL.appendingPathComponent("report.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: String])

        XCTAssertEqual(diagnostics["networkEventCount"], "1")
    }

    func testBundleSanitizesScreenshotFilenames() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let builder = DiagnosticsBundleBuilder(temporaryDirectory: tempDirectory)
        let materialization = try builder.build(
            report: makeReport(),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [],
            screenshots: [
                DiagnosticsAttachment(
                    data: Data("png".utf8),
                    filename: "../../secrets.png",
                    contentType: "image/png"
                )
            ]
        )
        defer {
            try? builder.cleanup(materialization)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: materialization.rootURL
                    .appendingPathComponent("screenshots/secrets.png")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("secrets.png").path
            )
        )
    }

    func testBundleKeepsDuplicateScreenshotFilenamesDistinct() throws {
        let builder = DiagnosticsBundleBuilder()
        let materialization = try builder.build(
            report: makeReport(),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [],
            screenshots: [
                DiagnosticsAttachment(
                    data: Data("first".utf8),
                    filename: "screenshot.png",
                    contentType: "image/png"
                ),
                DiagnosticsAttachment(
                    data: Data("second".utf8),
                    filename: "screenshot.png",
                    contentType: "image/png"
                )
            ]
        )
        defer {
            try? builder.cleanup(materialization)
        }

        let screenshotFiles = materialization.fileAttachments
            .map(\.fileURL)
            .filter { $0.deletingLastPathComponent().lastPathComponent == "screenshots" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertEqual(screenshotFiles.map(\.lastPathComponent), ["screenshot-2.png", "screenshot.png"])
        XCTAssertEqual(try Data(contentsOf: screenshotFiles[0]), Data("second".utf8))
        XCTAssertEqual(try Data(contentsOf: screenshotFiles[1]), Data("first".utf8))
    }

    func testBundleDoesNotLeakUnredactedSecrets() throws {
        let builder = DiagnosticsBundleBuilder()
        let materialization = try builder.build(
            report: makeReport(),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [
                NetworkEvent(
                    id: "1",
                    timing: .init(
                        startedAt: Date(timeIntervalSince1970: 0),
                        completedAt: Date(timeIntervalSince1970: 1),
                        durationMs: 1000
                    ),
                    target: .init(
                        method: "GET",
                        scheme: "https",
                        host: "example.com",
                        path: "/secure",
                        queryItems: [NetworkNameValuePair(name: "token", value: "<redacted>")]
                    ),
                    request: .init(
                        headers: [NetworkNameValuePair(name: "Authorization", value: "<redacted>")],
                        bodyPreview: nil,
                        bodySize: nil,
                        mimeType: nil,
                        httpVersion: "HTTP/1.1"
                    ),
                    response: nil,
                    failure: nil,
                    taskMetadata: [:]
                )
            ],
            screenshots: []
        )

        let har = try String(
            contentsOf: materialization.rootURL.appendingPathComponent("network.har")
        )
        XCTAssertFalse(har.contains("top-secret"))
        XCTAssertTrue(har.contains("<redacted>"))

        try builder.cleanup(materialization)
    }

    func testEmailOnlyDeliveryCanPrepareMailPayloadWhenAvailable() async throws {
        let submitter = makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: true,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Export failed",
                options: .init(includeTechnicalDetails: true, includeScreenshot: true)
            )
        )

        guard case let .needsUserAction(.email(email)) = outcome else {
            return XCTFail("Expected mail delivery")
        }

        XCTAssertEqual(email.recipients, ["support@example.com"])
        XCTAssertEqual(email.subject, "JustCards Report")
        XCTAssertTrue(email.body.contains("Export failed"))
        XCTAssertTrue(email.body.contains("App version/build"))
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "report.json" })
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "metadata.json" })
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "network.har" })
        XCTAssertNotNil(email.temporaryDirectoryURL)
    }

    func testMailUnavailableFallsBackToSharePayload() async throws {
        let submitter = makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Export failed",
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share fallback")
        }

        XCTAssertTrue(share.message.contains("Export failed"))
        XCTAssertGreaterThanOrEqual(share.itemURLs.count, 3)
        XCTAssertTrue(share.itemURLs.allSatisfy { !$0.hasDirectoryPath })
    }

    func testPendingDeliveryBundleRedactsCamelCaseDiagnosticsKeys() async throws {
        let submitter = makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Export failed",
                payload: .init(diagnostics: [
                    "accessToken": "top-secret",
                    "lastAction": "Tapped Export"
                ])
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share delivery")
        }

        let reportURL = try XCTUnwrap(
            share.itemURLs.first(where: { $0.lastPathComponent == "report.json" })
        )
        let data = try Data(contentsOf: reportURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: String])

        XCTAssertEqual(diagnostics["accessToken"], "<redacted>")
        XCTAssertEqual(diagnostics["lastAction"], "Tapped Export")
    }

    func testMacOSAlwaysUsesShareExportForEmailDelivery() async throws {
        let submitter = makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: true,
            platform: .macOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(kind: .bug, notes: "Export failed")
        )

        guard case .needsUserAction(.share) = outcome else {
            return XCTFail("Expected macOS share/export behavior")
        }
    }

    func testEndpointFailureDoesNotFallbackUnlessPolicyAllowsIt() async throws {
        let client = makeClient(statusCode: 500)
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .endpointWithEmailFallback(
                client,
                .standard(recipient: "support@example.com", appName: "JustCards"),
                fallbackPolicy: EmailFallbackPolicy(allowWhenNoEndpointConfigured: true, allowWhenEndpointFails: false)
            ),
            support: .init(
                networkRecorder: makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: true),
                platform: .iOS
            )
        )

        do {
            _ = try await submitter.submit(
                FeedbackSubmissionRequest(
                    kind: .bug,
                    notes: "Still broken",
                    options: .init(includeTechnicalDetails: true)
                )
            )
            XCTFail("Expected endpoint failure")
        } catch let error as AppReportClientError {
            XCTAssertEqual(error, .serverRejected(statusCode: 500))
        }
    }

    func testEndpointFailureCanFallbackWhenAllowed() async throws {
        let client = makeClient(statusCode: 500)
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .endpointWithEmailFallback(
                client,
                .standard(recipient: "support@example.com", appName: "JustCards"),
                fallbackPolicy: EmailFallbackPolicy(allowWhenNoEndpointConfigured: true, allowWhenEndpointFails: true)
            ),
            support: .init(
                networkRecorder: makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: false),
                platform: .iOS
            )
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Still broken",
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case .needsUserAction(.share) = outcome else {
            return XCTFail("Expected share fallback")
        }
    }

    func testEndpointModeDoesNotAttachDiagnosticsBundleUnlessExplicitlyConfigured() async throws {
        let transport = MockTransport(statusCode: 202)
        let client = AppReportClient(
            endpointURL: URL(string: "https://reports.example.com/v1/report")!,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            metadataProvider: FixedMetadataProvider.standard,
            transport: transport
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .endpoint(client),
            support: .init(
                networkRecorder: makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(attachBundleToEndpoint: false)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Broken export",
                options: .init(includeTechnicalDetails: true, includeScreenshot: true)
            )
        )

        let payload = try XCTUnwrap(transport.lastDecodedPayload())
        XCTAssertEqual(payload.attachments.count, 1)
        XCTAssertEqual(payload.attachments.first?.filename, "screenshot-1.png")
        XCTAssertFalse(payload.attachments.contains { $0.filename == "report.json" || $0.filename == "network.har" })
    }

    func testEndpointBundleAttachmentsAreCleanedUpAfterSubmission() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let transport = MockTransport(statusCode: 202)
        let client = AppReportClient(
            endpointURL: URL(string: "https://reports.example.com/v1/report")!,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            metadataProvider: FixedMetadataProvider.standard,
            transport: transport
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .endpoint(client),
            support: .init(
                networkRecorder: makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                bundleBuilder: DiagnosticsBundleBuilder(temporaryDirectory: tempDirectory),
                attachBundleToEndpoint: true
            )
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Broken export",
                options: .init(includeTechnicalDetails: true, includeScreenshot: true)
            )
        )

        let remainingItems = try FileManager.default.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingItems.isEmpty)
    }

    func testEndpointBundleModeDoesNotDuplicateScreenshotAttachments() async throws {
        let transport = MockTransport(statusCode: 202)
        let client = AppReportClient(
            endpointURL: URL(string: "https://reports.example.com/v1/report")!,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            metadataProvider: FixedMetadataProvider.standard,
            transport: transport
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .endpoint(client),
            support: .init(
                networkRecorder: makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(attachBundleToEndpoint: true)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Broken export",
                options: .init(includeTechnicalDetails: true, includeScreenshot: true)
            )
        )

        let payload = try XCTUnwrap(transport.lastDecodedPayload())
        XCTAssertEqual(
            payload.attachments.filter { $0.filename == "screenshot-1.png" }.count,
            1
        )
        XCTAssertTrue(payload.attachments.contains { $0.filename == "report.json" })
        XCTAssertTrue(payload.attachments.contains { $0.filename == "network.har" })
    }

    func testPendingDeliveryCleanupRemovesTemporaryDirectory() async throws {
        let submitter = makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                kind: .bug,
                notes: "Export failed",
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case let .needsUserAction(delivery) = outcome else {
            return XCTFail("Expected pending delivery")
        }

        let directoryURL: URL?
        switch delivery {
        case let .email(email):
            directoryURL = email.temporaryDirectoryURL
        case let .share(share):
            directoryURL = share.temporaryDirectoryURL
        }
        let temporaryDirectoryURL = try XCTUnwrap(directoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectoryURL.path))

        try DiagnosticsDeliveryCleanup.cleanup(delivery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectoryURL.path))
    }

    func testPackageManifestKeepsDiagnosticsOptional() throws {
        let packageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        let contents = try String(contentsOf: packageURL)

        XCTAssertTrue(contents.contains(".target(name: \"AppReportKit\")"))
        XCTAssertTrue(
            containsTargetDeclaration(
                named: "AppReportKitUI",
                dependency: "AppReportKit",
                in: contents
            )
        )
        XCTAssertTrue(
            containsTargetDeclaration(
                named: "AppReportKitDiagnostics",
                dependency: "AppReportKit",
                in: contents
            )
        )
    }

    private func makeDiagnosticsSubmitter(
        delivery: AppReportDelivery,
        mailAvailability: Bool,
        platform: DiagnosticsDeliveryPlatform
    ) -> AppReportDiagnosticsSubmitter {
        AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: delivery,
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: mailAvailability),
                platform: platform
            )
        )
    }

    private func makeReportBuilder() -> FeedbackReportBuilder {
        FeedbackReportBuilder(
            appId: "justcards",
            metadataProvider: FixedMetadataProvider.standard
        )
    }

    private func makeReport() -> FeedbackReport {
        makeReportBuilder().makeReport(
            kind: .bug,
            notes: "Broken export",
            severity: .high,
            email: "user@example.com",
            diagnostics: [
                "networkEventCount": "1",
                "lastAction": "Tapped Export"
            ]
        )
    }

    private func makeRecorder() -> NetworkRecorder {
        let recorder = NetworkRecorder(
            policy: NetworkCapturePolicy(
                capturesRequestBodyPreview: true,
                capturesResponseBodyPreview: true
            )
        )
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            var request = URLRequest(url: URL(string: "https://example.com/orders?token=secret")!)
            request.httpMethod = "POST"
            request.setValue("Bearer top-secret", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"password":"abc123"}"#.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            await recorder.record(
                request: request,
                startedAt: Date(timeIntervalSince1970: 0),
                outcome: .init(
                    response: response,
                    responseBody: Data(#"{"ok":true}"#.utf8),
                    completedAt: Date(timeIntervalSince1970: 1)
                )
            )
            semaphore.signal()
        }
        semaphore.wait()
        return recorder
    }

    private func makeClient(statusCode: Int) -> AppReportClient {
        AppReportClient(
            endpointURL: URL(string: "https://reports.example.com/v1/report")!,
            appId: "justcards",
            bearerToken: "TEST_APP_REPORT_KEY",
            metadataProvider: FixedMetadataProvider.standard,
            transport: MockTransport(statusCode: statusCode)
        )
    }

    private func makeNetworkEvent() -> NetworkEvent {
        NetworkEvent(
            id: "1",
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "GET",
                scheme: "https",
                host: "example.com",
                path: "/orders",
                queryItems: []
            ),
            request: .init(headers: [], bodyPreview: nil, bodySize: nil, mimeType: nil, httpVersion: "HTTP/1.1"),
            response: .init(
                statusCode: 200,
                statusText: "ok",
                headers: [],
                content: .init(mimeType: "application/json"),
                httpVersion: "",
                redirectURL: nil
            ),
            failure: nil,
            taskMetadata: [:]
        )
    }

    private func containsTargetDeclaration(
        named targetName: String,
        dependency: String,
        in contents: String
    ) -> Bool {
        let normalizedContents = contents.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let declarationPrefix = #".target( name: "\#(targetName)", dependencies: ["\#(dependency)"]"#
        return normalizedContents.contains(declarationPrefix)
    }
}

private struct FixedDiagnosticsProvider: FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String] {
        ["lastAction": "Tapped Export"]
    }
}

private struct StaticScreenshotProvider: FeedbackScreenshotProviding {
    func makeScreenshots() throws -> [FeedbackScreenshot] {
        [
            FeedbackScreenshot(
                data: Data("png".utf8),
                filename: "screenshot-1.png",
                contentType: "image/png",
                description: "Current screen"
            )
        ]
    }
}

private struct StaticMailAvailabilityChecker: MailAvailabilityChecking {
    let value: Bool

    func canSendMail() -> Bool {
        value
    }
}

private struct FixedMetadataProvider: FeedbackMetadataProviding {
    let metadata: FeedbackMetadata

    static let standard = FixedMetadataProvider(
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
                locale: "en_AU"
            )
        )
    )

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
    private let statusCode: Int

    var lastBody: Data?

    init(statusCode: Int) {
        self.statusCode = statusCode
    }

    func send(request _: URLRequest, body: Data) async throws -> AppReportTransportResponse {
        lastBody = body
        return AppReportTransportResponse(statusCode: statusCode, data: Data())
    }

    func lastDecodedPayload() throws -> FeedbackReport? {
        guard let lastBody else {
            return nil
        }

        return try JSONDecoder().decode(FeedbackReport.self, from: lastBody)
    }
}
