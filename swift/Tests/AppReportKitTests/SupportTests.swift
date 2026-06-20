import Foundation
import XCTest
@testable import AppReportKit

final class SupportTests: XCTestCase {
    func testEmptyFeedbackDiagnosticsProviderReturnsEmptyDictionary() {
        XCTAssertEqual(EmptyFeedbackDiagnosticsProvider().makeDiagnostics(), [:])
    }

    func testFeedbackMetadataStoresValuesAndRoundTripsThroughCodable() throws {
        let metadata = FeedbackMetadata(
            app: .init(
                version: "1.2.3",
                build: "42",
                clientVersion: "0.1.0",
                screen: "Composer"
            ),
            device: .init(
                osName: "macOS",
                osVersion: "15.0",
                model: "Mac14,7",
                locale: "en_AU"
            )
        )

        XCTAssertEqual(metadata.appVersion, "1.2.3")
        XCTAssertEqual(metadata.build, "42")
        XCTAssertEqual(metadata.osName, "macOS")
        XCTAssertEqual(metadata.osVersion, "15.0")
        XCTAssertEqual(metadata.deviceModel, "Mac14,7")
        XCTAssertEqual(metadata.locale, "en_AU")
        XCTAssertEqual(metadata.clientVersion, "0.1.0")
        XCTAssertEqual(metadata.screen, "Composer")

        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(FeedbackMetadata.self, from: encoded)
        XCTAssertEqual(decoded, metadata)
    }

    func testSystemFeedbackMetadataProviderUsesInjectedContext() {
        let provider = SystemFeedbackMetadataProvider(
            bundle: .init(),
            localeProvider: { Locale(identifier: "fr_FR") },
            operatingSystemProvider: { OperatingSystemSnapshot(name: "macOS", version: "14.5") },
            deviceModelProvider: { "MacBookPro18,1" }
        )

        let metadata = provider.makeMetadata(screen: "Inbox")

        XCTAssertEqual(metadata.appVersion, "unknown")
        XCTAssertEqual(metadata.build, "unknown")
        XCTAssertEqual(metadata.clientVersion, AppReportKitVersion.current)
        XCTAssertEqual(metadata.screen, "Inbox")
        XCTAssertEqual(metadata.osName, "macOS")
        XCTAssertEqual(metadata.osVersion, "14.5")
        XCTAssertEqual(metadata.deviceModel, "MacBookPro18,1")
        XCTAssertEqual(metadata.locale, "fr_FR")
    }

    func testOperatingSystemSnapshotCurrentAndDeviceModelArePopulated() {
        let snapshot = OperatingSystemSnapshot.current

        XCTAssertEqual(snapshot.name, "macOS")
        XCTAssertFalse(snapshot.version.isEmpty)
        XCTAssertFalse(DeviceModel.current.isEmpty)
    }

    func testURLSessionTransportForwardsBodyAndReturnsHTTPResponse() async throws {
        let session = makeSession(response: .http(statusCode: 204), recordedRequest: nil)
        let transport = URLSessionTransport(session: session)
        let request = URLRequest(url: URL(string: "https://example.com/report")!)
        let body = Data(#"{"hello":"world"}"#.utf8)

        let response = try await transport.send(request: request, body: body)

        XCTAssertEqual(response.statusCode, 204)
        XCTAssertEqual(response.data, Data())
    }

    func testURLSessionTransportThrowsWhenResponseIsNotHTTP() async throws {
        let session = makeSession(response: .plain, recordedRequest: nil)
        let transport = URLSessionTransport(session: session)
        let request = URLRequest(url: URL(string: "https://example.com/report")!)

        do {
            _ = try await transport.send(request: request, body: Data())
            XCTFail("Expected invalidResponse error")
        } catch let error as AppReportClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testFeedbackReportBuilderUsesInjectedMetadataAndAppId() {
        let builder = FeedbackReportBuilder(
            appId: "justcards",
            metadataProvider: FixedMetadataProvider(
                metadata: FeedbackMetadata(
                    app: .init(
                        version: "1.2.3",
                        build: "42",
                        clientVersion: "0.2.0",
                        screen: "Composer"
                    ),
                    device: .init(
                        osName: "iOS",
                        osVersion: "18.5",
                        model: "iPhone16,2",
                        locale: "en_AU"
                    )
                )
            )
        )

        let report = builder.makeReport(
            details: .init(
                kind: .feedback,
                notes: "Looks good"
            ),
            diagnostics: ["context": "preview"]
        )

        XCTAssertEqual(report.appId, "justcards")
        XCTAssertEqual(report.metadata.appVersion, "1.2.3")
        XCTAssertEqual(report.diagnostics?["context"], "preview")
    }

    func testPreparedAppReportSubmissionBuildsTypedPayloadMetadataAndAttachments() {
        let request = FeedbackSubmissionRequest(
            details: .init(
                kind: .bug,
                notes: "Broken export",
                severity: .high,
                email: " person@example.com ",
                screen: "InvoiceEditor"
            ),
            payload: .init(
                diagnostics: ["lastAction": "Tapped Export"],
                attachments: [
                    FeedbackAttachment(
                        filename: "log.txt",
                        contentType: "text/plain",
                        data: Data("log".utf8)
                    )
                ]
            ),
            screenshotAttachments: [
                FeedbackAttachment(
                    filename: "screenshot.png",
                    contentType: "image/png",
                    data: Data("png".utf8)
                )
            ]
        )

        let prepared = request.preparedAppReportSubmission(
            metadataProvider: FixedMetadataProvider(
                metadata: FeedbackMetadata(
                    app: .init(
                        version: "1.2.3",
                        build: "42",
                        clientVersion: "0.2.0",
                        screen: "InvoiceEditor"
                    ),
                    device: .init(
                        osName: "iOS",
                        osVersion: "18.5",
                        model: "iPhone16,2",
                        locale: "en_AU"
                    )
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 123)
        )

        XCTAssertEqual(prepared.report.type, "bug")
        XCTAssertEqual(prepared.report.context, "InvoiceEditor")
        XCTAssertEqual(prepared.report.title, "Bug")
        XCTAssertEqual(prepared.report.notes, "Broken export")
        XCTAssertEqual(prepared.report.reporterEmail, "person@example.com")
        XCTAssertEqual(prepared.report.severity, "high")
        XCTAssertEqual(prepared.metadata.appVersion, "1.2.3")
        XCTAssertEqual(prepared.metadata.buildNumber, "42")
        XCTAssertEqual(prepared.metadata.localeIdentifier, "en_AU")
        XCTAssertEqual(prepared.metadata.timezoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(prepared.metadata.capturedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(prepared.attachments.map(\.kind), [.attachment, .screenshot])
        XCTAssertEqual(prepared.attachments.map(\.fileName), ["log.txt", "screenshot.png"])
        XCTAssertEqual(prepared.attachments.map(\.mimeType), ["text/plain", "image/png"])
        XCTAssertNil(prepared.diagnosticsBundle)
    }

    func testFeedbackFormSupportOptionsDefaultToDisabled() {
        XCTAssertEqual(FeedbackFormSupportOptions.disabled, FeedbackFormSupportOptions())
    }

    func testSwiftSourcesDoNotContainGitHubEndpoints() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: nil
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            let contents = try String(contentsOf: fileURL)
            XCTAssertFalse(contents.contains("api.github.com"), "Unexpected GitHub endpoint in \(fileURL.lastPathComponent)")
            XCTAssertFalse(contents.contains("github.com"), "Unexpected GitHub URL in \(fileURL.lastPathComponent)")
        }
    }

    func testAppReportKitUISourcesRemainLightweightWithoutNetworkCaptureLogic() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiSourcesURL = rootURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("AppReportKitUI", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: uiSourcesURL,
            includingPropertiesForKeys: nil
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            let contents = try String(contentsOf: fileURL)
            XCTAssertFalse(
                contents.contains("AppReportNetworkCapture"),
                "Unexpected network-capture type in \(fileURL.lastPathComponent)"
            )
            XCTAssertFalse(
                contents.contains("NetworkRecorder"),
                "Unexpected network-capture type in \(fileURL.lastPathComponent)"
            )
            XCTAssertFalse(
                contents.contains("capture(") && contents.contains("URLSession"),
                "Unexpected URLSession capture plumbing in \(fileURL.lastPathComponent)"
            )
            if fileURL.lastPathComponent == "FeedbackForm.swift" {
                XCTAssertTrue(contents.contains(".scaledToFit()"), "Screenshot preview should fit within its frame")
                XCTAssertFalse(contents.contains(".scaledToFill()"), "Screenshot preview should no longer crop to fill")
            }
        }
    }

    private func makeSession(response: StubURLResponse, recordedRequest: URLRequest?) -> URLSession {
        StubURLProtocol.handler = { request in
            switch response {
            case let .http(statusCode):
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            case .plain:
                return (URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), Data())
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
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

private enum StubURLResponse {
    case http(statusCode: Int)
    case plain
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
