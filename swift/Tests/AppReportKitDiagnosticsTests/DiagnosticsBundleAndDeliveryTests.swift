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

    func testBundleIncludesBreadcrumbsFileWhenProvided() throws {
        let builder = DiagnosticsBundleBuilder()
        let materialization = try builder.build(
            report: makeReport(
                breadcrumbs: [
                    FeedbackBreadcrumb(
                        timestamp: Date(timeIntervalSince1970: 0),
                        title: "Opened report screen"
                    )
                ]
            ),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [],
            screenshots: []
        )
        defer {
            try? builder.cleanup(materialization)
        }

        let fileURL = materialization.rootURL.appendingPathComponent("breadcrumbs.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let content = try String(contentsOf: fileURL)
        XCTAssertTrue(content.contains("Opened report screen"))
    }

    func testBundleOmitsBreadcrumbsFileWhenNoBreadcrumbs() throws {
        let builder = DiagnosticsBundleBuilder()
        let materialization = try builder.build(
            report: makeReport(),
            submittedAt: Date(timeIntervalSince1970: 0),
            networkEvents: [],
            screenshots: []
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: materialization.rootURL
                    .appendingPathComponent("breadcrumbs.jsonl")
                    .path
            )
        )

        try builder.cleanup(materialization)
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
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: true,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
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
        XCTAssertFalse(email.body.contains("User email"))
        XCTAssertFalse(email.body.contains("Not provided"))
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "report.json" })
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "metadata.json" })
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "network.har" })
        XCTAssertNotNil(email.temporaryDirectoryURL)
    }

    func testMailUnavailableFallsBackToSharePayload() async throws {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share fallback")
        }

        XCTAssertTrue(share.message.contains("Export failed"))
        XCTAssertEqual(share.itemURLs.count, 1)
        XCTAssertTrue(share.itemURLs.allSatisfy { !$0.hasDirectoryPath })
        XCTAssertEqual(share.itemURLs.first?.pathExtension, "zip")
    }

    func testCustomDeliveryReceivesPreparedSubmissionWithBundleAndAttachments() async throws {
        let handler = RecordingSubmissionHandler()
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(handler, emailFallback: nil),
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(platform: .iOS, allowEndpointScreenshotAttachments: false)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed",
                    severity: .high,
                    email: "user@example.com",
                    screen: "InvoiceEditor"
                ),
                options: .init(includeTechnicalDetails: true, includeScreenshot: true),
                payload: .init(
                    attachments: [
                        FeedbackAttachment(
                            filename: "log.txt",
                            contentType: "text/plain",
                            data: Data("log".utf8)
                        )
                    ]
                )
            )
        )

        let maybeSubmission = await handler.firstSubmission()
        let submission = try XCTUnwrap(maybeSubmission)
        XCTAssertEqual(submission.report.type, "bug")
        XCTAssertEqual(submission.report.context, "InvoiceEditor")
        XCTAssertEqual(submission.report.title, "Bug")
        XCTAssertEqual(submission.report.notes, "Export failed")
        XCTAssertEqual(submission.report.reporterEmail, "user@example.com")
        XCTAssertEqual(submission.report.severity, "high")
        XCTAssertEqual(submission.attachments.map(\.kind), [.attachment, .screenshot])
        XCTAssertEqual(submission.attachments.map(\.fileName), ["log.txt", "screenshot-1.png"])
        XCTAssertTrue(submission.attachments.contains { $0.fileName == "screenshot-1.png" })
        XCTAssertNotNil(submission.diagnosticsBundle)
        XCTAssertTrue(submission.diagnosticsBundle?.fileName.hasSuffix(".zip") == true)
        XCTAssertEqual(submission.diagnosticsBundle?.mimeType, "application/zip")
    }

    func testDiagnosticsSubmitterExposesConfiguredScreenshotProviderToFeedbackForm() throws {
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(RecordingSubmissionHandler(), emailFallback: nil),
            support: .init(screenshotProvider: StaticScreenshotProvider())
        )

        let screenshotProvider = submitter as FeedbackScreenshotProviding
        let screenshots = try screenshotProvider.makeScreenshots()

        XCTAssertEqual(screenshots.count, 1)
        XCTAssertEqual(screenshots.first?.filename, "screenshot-1.png")
        XCTAssertEqual(screenshots.first?.contentType, "image/png")
        XCTAssertEqual(screenshots.first?.data, Data("png".utf8))
    }

    func testDiagnosticsSubmitterReturnsNoScreenshotsWithoutConfiguredProvider() throws {
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(RecordingSubmissionHandler(), emailFallback: nil)
        )

        XCTAssertTrue(try submitter.makeScreenshots().isEmpty)
    }

    func testCustomDeliveryWithoutLogsSkipsDiagnosticsBundle() async throws {
        let handler = RecordingSubmissionHandler()
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(handler, emailFallback: nil),
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder()
            ),
            configuration: .init(platform: .iOS)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: false)
            )
        )

        let maybeSubmission = await handler.firstSubmission()
        let submission = try XCTUnwrap(maybeSubmission)
        XCTAssertNil(submission.diagnosticsBundle)
    }

    func testCustomDeliveryCanRequireUserChoiceBeforeSendingLogs() async throws {
        let handler = RecordingSubmissionHandler(
            capabilities: [.images]
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(
                handler,
                emailFallback: .standard(
                    recipient: "support@example.com",
                    appName: "JustCards"
                )
            ),
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: true),
                platform: .iOS
            )
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: true, includeScreenshot: true)
            )
        )

        guard case let .needsConfirmation(confirmation) = outcome else {
            return XCTFail("Expected logs confirmation")
        }

        XCTAssertEqual(confirmation.unsupported, [.files])
        guard case let .email(email)? = confirmation.alternateDelivery else {
            return XCTFail("Expected alternate email delivery")
        }
        XCTAssertTrue(email.attachments.contains { $0.fileURL.lastPathComponent == "network.har" })
        let firstSubmission = await handler.firstSubmission()
        XCTAssertNil(firstSubmission)
    }

    func testCustomDeliveryStillReturnsConfirmationWhenAlternatePreparationFails() async throws {
        let handler = RecordingSubmissionHandler(
            capabilities: [.images]
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(
                handler,
                emailFallback: .standard(
                    recipient: "support@example.com",
                    appName: "JustCards"
                )
            ),
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder()
            ),
            configuration: .init(
                bundlePackager: ThrowingPackager(),
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: false),
                platform: .iOS
            )
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case let .needsConfirmation(confirmation) = outcome else {
            return XCTFail("Expected logs confirmation")
        }

        XCTAssertEqual(confirmation.unsupported, [.files])
        XCTAssertNil(confirmation.alternateDelivery)
        let firstSubmission = await handler.firstSubmission()
        XCTAssertNil(firstSubmission)
    }

    func testCustomDeliveryCanRequireUserChoiceBeforeSendingImages() async throws {
        let handler = RecordingSubmissionHandler(
            capabilities: [.files]
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(
                handler,
                emailFallback: .standard(
                    recipient: "support@example.com",
                    appName: "JustCards"
                )
            ),
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: true),
                platform: .iOS
            )
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: false, includeScreenshot: true)
            )
        )

        guard case let .needsConfirmation(confirmation) = outcome else {
            return XCTFail("Expected image confirmation")
        }

        XCTAssertEqual(confirmation.unsupported, [.images])
        let firstSubmission = await handler.firstSubmission()
        XCTAssertNil(firstSubmission)
    }

    func testCustomDeliveryWithNoLogsDoesNotRequireFileCapability() async throws {
        let handler = RecordingSubmissionHandler(
            capabilities: [.images]
        )
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .custom(handler, emailFallback: nil),
            support: .init(),
            configuration: .init(platform: .iOS)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: true, includeScreenshot: false)
            )
        )

        let maybeSubmission = await handler.firstSubmission()
        let submission = try XCTUnwrap(maybeSubmission)
        XCTAssertNil(submission.diagnosticsBundle)
    }

    func testDiagnosticsSubmitterDefaultsToEmailSubmissionPolicyForEmailDelivery() async {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: true,
            platform: .iOS
        )
        let expectedPolicy = FeedbackFormPolicy(
            .init(emailOptions: .init(allowsEmail: false, requiresEmail: false))
        )
        XCTAssertEqual(submitter.feedbackFormPolicy, expectedPolicy)
    }

    func testPendingDeliveryBundleRedactsCamelCaseDiagnosticsKeys() async throws {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                payload: .init(diagnostics: [
                    "accessToken": "top-secret",
                    "lastAction": "Tapped Export"
                ])
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share delivery")
        }

        let packageURL = try XCTUnwrap(share.itemURLs.first)
        let reportData = try readZipEntry(from: packageURL, named: "report.json")
        let data = try XCTUnwrap(reportData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: String])

        XCTAssertEqual(diagnostics["accessToken"], "<redacted>")
        XCTAssertEqual(diagnostics["lastAction"], "Tapped Export")
    }

    func testSingleFileSharePackageContainsExpectedArtifacts() async throws {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: true, includeScreenshot: true)
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share delivery")
        }
        let packageURL = try XCTUnwrap(share.itemURLs.first)
        let packageEntries = try listZipEntries(at: packageURL)

        XCTAssertTrue(packageEntries.contains("report.json"))
        XCTAssertTrue(packageEntries.contains("metadata.json"))
        XCTAssertTrue(packageEntries.contains("README.txt"))
        XCTAssertTrue(packageEntries.contains("network.har"))
        XCTAssertTrue(
            packageEntries.contains("screenshots/screenshot-1.png"),
            "Entries: \(packageEntries)"
        )
        XCTAssertFalse(packageEntries.contains("screenshots"))
        XCTAssertEqual(share.itemURLs.count, 1)

        guard let firstEntryName = packageEntries.first(where: { $0 == "report.json" }) else {
            return XCTFail("Expected report.json entry")
        }
        XCTAssertEqual(firstEntryName, "report.json")
    }

    func testSharePackageDoesNotContainUnredactedSecrets() async throws {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                payload: .init(diagnostics: ["authToken": "top-secret", "safeKey": "value"])
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share delivery")
        }

        let packageURL = try XCTUnwrap(share.itemURLs.first)
        let reportData = try XCTUnwrap(readZipEntry(from: packageURL, named: "report.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: reportData) as? [String: Any])
        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: String])

        XCTAssertEqual(diagnostics["authToken"], "<redacted>")
        XCTAssertEqual(diagnostics["safeKey"], "value")
    }

    func testSharePackageRedactsBreadcrumbMetadata() async throws {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS,
            breadcrumbProvider: StaticBreadcrumbProvider()
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
                options: .init(includeTechnicalDetails: true)
            )
        )

        guard case let .needsUserAction(.share(share)) = outcome else {
            return XCTFail("Expected share delivery")
        }

        let packageURL = try XCTUnwrap(share.itemURLs.first)
        let reportData = try XCTUnwrap(readZipEntry(from: packageURL, named: "report.json"))
        let reportJSON = try JSONSerialization.jsonObject(with: reportData) as? [String: Any]
        let json = try XCTUnwrap(reportJSON)
        let breadcrumbs = try XCTUnwrap(json["breadcrumbs"] as? [[String: Any]])
        let firstBreadcrumb = try XCTUnwrap(breadcrumbs.first)
        let metadata = try XCTUnwrap(firstBreadcrumb["metadata"] as? [String: String])

        XCTAssertEqual(metadata["authToken"], "<redacted>")
        XCTAssertEqual(metadata["route"], "safe-route")
        XCTAssertFalse(metadata.values.contains("top-secret"))

        let breadcrumbsData = try XCTUnwrap(readZipEntry(from: packageURL, named: "breadcrumbs.jsonl"))
        let breadcrumbsText = try XCTUnwrap(String(data: breadcrumbsData, encoding: .utf8))
        XCTAssertTrue(breadcrumbsText.contains("\"authToken\":\"<redacted>\""))
        XCTAssertFalse(breadcrumbsText.contains("top-secret"))
    }

    func testMacOSAlwaysUsesShareExportForEmailDelivery() async throws {
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: true,
            platform: .macOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(details: .init(kind: .bug, notes: "Export failed"))
        )

        guard case .needsUserAction(.share) = outcome else {
            return XCTFail("Expected macOS share/export behavior")
        }
    }

    func testSubmissionRouteReflectsPlatformAndMailAvailability() async {
        let iOSEmailRoute = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: true,
            platform: .iOS
        )
        XCTAssertEqual(iOSEmailRoute.feedbackSubmissionRoute, .email)

        let iOSShareRoute = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )
        XCTAssertEqual(iOSShareRoute.feedbackSubmissionRoute, .share)

        let macOSExportRoute = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .macOS
        )
        XCTAssertEqual(macOSExportRoute.feedbackSubmissionRoute, .export)

        let unavailableRoute = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .other
        )
        XCTAssertEqual(unavailableRoute.feedbackSubmissionRoute, .unavailable)
    }

    func testEndpointFailureDoesNotFallbackUnlessPolicyAllowsIt() async throws {
        let client = makeClient(statusCode: 500)
        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .endpointWithEmailFallback(
                client,
                .standard(recipient: "support@example.com", appName: "JustCards"),
                fallbackPolicy: EmailFallbackPolicy(allowWhenEndpointFails: false)
            ),
            support: .init(
                networkRecorder: await makeRecorder(),
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
                    details: .init(
                        kind: .bug,
                        notes: "Still broken"
                    ),
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
                fallbackPolicy: EmailFallbackPolicy(allowWhenEndpointFails: true)
            ),
            support: .init(
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: false),
                platform: .iOS
            )
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Still broken"
                ),
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
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(attachBundleToEndpoint: false)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Broken export"
                ),
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
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                bundleBuilder: DiagnosticsBundleBuilder(temporaryDirectory: tempDirectory),
                attachBundleToEndpoint: true
            )
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Broken export"
                ),
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
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(attachBundleToEndpoint: true)
        )

        _ = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Broken export"
                ),
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
        let submitter = await makeDiagnosticsSubmitter(
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            mailAvailability: false,
            platform: .iOS
        )

        let outcome = try await submitter.submit(
            FeedbackSubmissionRequest(
                details: .init(
                    kind: .bug,
                    notes: "Export failed"
                ),
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

    func testPendingDeliveryCleansUpBundleWhenPackagingFails() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let submitter = AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider()
            ),
            configuration: .init(
                bundleBuilder: DiagnosticsBundleBuilder(temporaryDirectory: tempDirectory),
                bundlePackager: ThrowingPackager(),
                mailAvailabilityChecker: StaticMailAvailabilityChecker(value: false),
                platform: .iOS
            )
        )

        do {
            _ = try await submitter.submit(
                FeedbackSubmissionRequest(
                    details: .init(
                        kind: .bug,
                        notes: "Export failed"
                    ),
                    options: .init(includeTechnicalDetails: true)
                )
            )
            XCTFail("Expected packaging failure")
        } catch {
            let remainingItems = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil
            )
            XCTAssertTrue(remainingItems.isEmpty)
        }
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
        platform: DiagnosticsDeliveryPlatform,
        breadcrumbProvider: FeedbackBreadcrumbProviding? = nil
    ) async -> AppReportDiagnosticsSubmitter {
        AppReportDiagnosticsSubmitter(
            reportBuilder: makeReportBuilder(),
            delivery: delivery,
            support: .init(
                diagnosticsProvider: FixedDiagnosticsProvider(),
                networkRecorder: await makeRecorder(),
                screenshotProvider: StaticScreenshotProvider(),
                breadcrumbProvider: breadcrumbProvider
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

    private func makeReport(
        breadcrumbs: [FeedbackBreadcrumb] = []
    ) -> FeedbackReport {
        makeReportBuilder().makeReport(
            details: .init(
                kind: .bug,
                notes: "Broken export",
                severity: .high,
                email: "user@example.com"
            ),
            diagnostics: [
                "networkEventCount": "1",
                "lastAction": "Tapped Export"
            ],
            breadcrumbs: breadcrumbs
        )
    }

    private func makeRecorder() async -> NetworkRecorder {
        let recorder = NetworkRecorder(
            policy: NetworkCapturePolicy(
                capturesRequestBodyPreview: true,
                capturesResponseBodyPreview: true
            )
        )
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

    private func listZipEntries(at zipURL: URL) throws -> [String] {
        let data = try Data(contentsOf: zipURL)
        guard let eocdStart = locateEOCD(in: data) else {
            return []
        }

        let totalEntries = Int(readUInt16(from: data, at: eocdStart + 10))
        let centralDirectoryOffset = Int(readUInt32(from: data, at: eocdStart + 16))
        var cursor = centralDirectoryOffset
        var names: [String] = []

        for _ in 0..<totalEntries {
            let signature = readUInt32(from: data, at: cursor)
            guard signature == 0x0201_4b50 else {
                break
            }

            let nameLength = Int(readUInt16(from: data, at: cursor + 28))
            let extraLength = Int(readUInt16(from: data, at: cursor + 30))
            let commentLength = Int(readUInt16(from: data, at: cursor + 32))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            let nameData = data.subdata(in: nameStart..<nameEnd)
            if let name = String(data: nameData, encoding: .utf8) {
                names.append(name)
            }

            cursor = nameEnd + extraLength + commentLength
        }

        return names
    }

    private func readZipEntry(from zipURL: URL, named entryName: String) throws -> Data? {
        let data = try Data(contentsOf: zipURL)
        guard let eocdStart = locateEOCD(in: data) else {
            return nil
        }

        let totalEntries = Int(readUInt16(from: data, at: eocdStart + 10))
        let centralDirectoryOffset = Int(readUInt32(from: data, at: eocdStart + 16))
        var cursor = centralDirectoryOffset

        for _ in 0..<totalEntries {
            guard readUInt32(from: data, at: cursor) == 0x0201_4b50 else {
                return nil
            }

            let nameLength = Int(readUInt16(from: data, at: cursor + 28))
            let extraLength = Int(readUInt16(from: data, at: cursor + 30))
            let commentLength = Int(readUInt16(from: data, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32(from: data, at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let centralName = String(data: nameData, encoding: .utf8)

            let compressedSize = Int(readUInt32(from: data, at: cursor + 20))
            if centralName == entryName {
                let localNameLen = Int(readUInt16(from: data, at: localHeaderOffset + 26))
                let localExtraLen = Int(readUInt16(from: data, at: localHeaderOffset + 28))
                let localDataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
                let localDataEnd = localDataStart + compressedSize
                return data.subdata(in: localDataStart..<localDataEnd)
            }

            cursor = nameEnd + extraLength + commentLength
        }

        return nil
    }

    private func locateEOCD(in data: Data) -> Int? {
        if data.count < 22 {
            return nil
        }

        let maxOffset = max(0, data.count - 66_000)
        if data.count < maxOffset + 4 {
            return nil
        }

        for index in stride(from: data.count - 4, through: maxOffset, by: -1) {
            if data[index] == 0x50,
               data[index + 1] == 0x4b,
               data[index + 2] == 0x05,
               data[index + 3] == 0x06 {
                return index
            }
        }

        return nil
    }

    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard data.count >= offset + 2 else {
            return 0
        }

        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else {
            return 0
        }

        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private struct ThrowingPackager: DiagnosticsBundlePackager {
    func package(at _: URL, filename _: String) throws -> URL {
        throw NSError(domain: "DiagnosticsBundlePackagerTest", code: 1)
    }
}

private actor RecordingSubmissionHandler: AppReportSubmissionHandling {
    private var submissions: [PreparedAppReportSubmission] = []
    nonisolated let capabilities: AppReportSubmissionCapabilities

    init(
        capabilities: AppReportSubmissionCapabilities = .all
    ) {
        self.capabilities = capabilities
    }

    func submit(_ submission: PreparedAppReportSubmission) async throws {
        submissions.append(submission)
    }

    func firstSubmission() -> PreparedAppReportSubmission? {
        submissions.first
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

private struct StaticBreadcrumbProvider: FeedbackBreadcrumbProviding {
    func currentBreadcrumbs() async -> [FeedbackBreadcrumb] {
        [
            FeedbackBreadcrumb(
                timestamp: Date(timeIntervalSince1970: 0),
                title: "Submitted bug report",
                metadata: [
                    "authToken": "top-secret",
                    "route": "safe-route"
                ]
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
