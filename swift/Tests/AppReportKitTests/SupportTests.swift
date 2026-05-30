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