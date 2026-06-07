import Foundation
import XCTest
@testable import AppReportKit
@testable import AppReportKitDiagnostics

final class NetworkCaptureTests: XCTestCase {
    func testHTTPVersionResolverNormalizesCommonNetworkProtocolNames() {
        XCTAssertEqual(HTTPVersionResolver.resolve(from: "http/1.1"), "HTTP/1.1")
        XCTAssertEqual(HTTPVersionResolver.resolve(from: "h2"), "HTTP/2")
        XCTAssertEqual(HTTPVersionResolver.resolve(from: "h3"), "HTTP/3")
        XCTAssertEqual(HTTPVersionResolver.resolve(from: "HTTP/1.0"), "HTTP/1.0")
        XCTAssertNil(HTTPVersionResolver.resolve(from: "quic"))
        XCTAssertNil(HTTPVersionResolver.resolve(from: nil))
    }

    func testRecorderRedactsSensitiveHeadersQueryItemsAndJSONBodyBeforeRetention() async throws {
        let policy = NetworkCapturePolicy(
            capturesRequestBodyPreview: true,
            capturesResponseBodyPreview: true
        )
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(url: URL(string: "https://example.com/orders?access_token=secret-token")!)
        request.httpMethod = "POST"
        request.setValue("Bearer top-secret", forHTTPHeaderField: "Authorization")
        request.setValue("session=value", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"password":"abc123","title":"Preview"}"#.utf8)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Set-Cookie": "refresh-token=value",
                "Content-Type": "application/json"
            ]
        )!

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            outcome: .init(
                response: response,
                responseBody: Data(#"{"token":"response-secret","ok":true}"#.utf8),
                completedAt: Date(timeIntervalSince1970: 1)
            )
        )

        let snapshot = await recorder.snapshot()
        let event = try XCTUnwrap(snapshot.first)
        XCTAssertEqual(event.queryItems.first?.value, "<redacted>")
        XCTAssertEqual(event.request.headers.first(where: { $0.name == "Authorization" })?.value, "<redacted>")
        XCTAssertEqual(event.request.headers.first(where: { $0.name == "Cookie" })?.value, "<redacted>")
        XCTAssertEqual(event.response?.headers.first(where: { $0.name == "Set-Cookie" })?.value, "<redacted>")
        XCTAssertTrue(event.request.bodyPreview?.contains(#""password":"<redacted>""#) == true)
        XCTAssertTrue(event.request.bodyPreview?.contains(#""title":"Preview""#) == true)
        XCTAssertTrue(event.response?.bodyPreview?.contains(#""token":"<redacted>""#) == true)
        XCTAssertTrue(event.response?.bodyPreview?.contains(#""ok":true"#) == true)
    }

    func testRedactionIsCaseInsensitive() async throws {
        let policy = NetworkCapturePolicy(capturesRequestBodyPreview: true)
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(url: URL(string: "https://example.com/search?API_Key=abc")!)
        request.httpMethod = "POST"
        request.setValue("abc", forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"PASSWORD":"1234"}"#.utf8)

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            outcome: .init(completedAt: Date(timeIntervalSince1970: 1))
        )

        let snapshot = await recorder.snapshot()
        let event = try XCTUnwrap(snapshot.first)
        XCTAssertEqual(event.queryItems.first?.value, "<redacted>")
        XCTAssertEqual(event.request.headers.first(where: { $0.name == "x-api-key" })?.value, "<redacted>")
        XCTAssertTrue(event.request.bodyPreview?.contains(#""PASSWORD":"<redacted>""#) == true)
    }

    func testRedactionNormalizesCamelCaseSecretKeysAcrossQueryBodyAndMetadata() async throws {
        let policy = NetworkCapturePolicy(capturesRequestBodyPreview: true)
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(
            url: URL(
                string: "https://example.com/search?accessToken=abc&clientSecret=def&sessionId=ghi"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("header-secret", forHTTPHeaderField: "AuthToken")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"refreshToken":"123","clientSecret":"456","title":"Preview"}"#.utf8)

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            context: .init(
                taskMetadata: [
                    "authToken": "metadata-secret",
                    "lastAction": "Tapped Export"
                ]
            ),
            outcome: .init(completedAt: Date(timeIntervalSince1970: 1))
        )

        let snapshot = await recorder.snapshot()
        let event = try XCTUnwrap(snapshot.first)

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: event.queryItems.map { ($0.name, $0.value) })["accessToken"],
            "<redacted>"
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: event.queryItems.map { ($0.name, $0.value) })["clientSecret"],
            "<redacted>"
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: event.queryItems.map { ($0.name, $0.value) })["sessionId"],
            "<redacted>"
        )
        XCTAssertEqual(
            event.request.headers.first(where: { $0.name == "AuthToken" })?.value,
            "<redacted>"
        )
        XCTAssertTrue(event.request.bodyPreview?.contains(#""refreshToken":"<redacted>""#) == true)
        XCTAssertTrue(event.request.bodyPreview?.contains(#""clientSecret":"<redacted>""#) == true)
        XCTAssertTrue(event.request.bodyPreview?.contains(#""title":"Preview""#) == true)
        XCTAssertEqual(event.taskMetadata["authToken"], "<redacted>")
        XCTAssertEqual(event.taskMetadata["lastAction"], "Tapped Export")
    }

    func testRecorderStoresSuppliedHTTPVersions() async throws {
        let recorder = NetworkRecorder()
        let request = URLRequest(url: URL(string: "https://example.com/orders")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/orders")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            context: .init(requestHTTPVersion: "HTTP/2"),
            outcome: .init(
                response: response,
                completedAt: Date(timeIntervalSince1970: 1),
                responseHTTPVersion: "HTTP/2"
            )
        )

        let snapshot = await recorder.snapshot()
        let event = try XCTUnwrap(snapshot.first)
        XCTAssertEqual(event.request.httpVersion, "HTTP/2")
        XCTAssertEqual(event.response?.httpVersion, "HTTP/2")
    }

    func testInstalledCaptureInterceptsURLSessionConfigurationTraffic() async throws {
        let recorder = NetworkRecorder(
            policy: NetworkCapturePolicy(
                capturesRequestBodyPreview: true,
                capturesResponseBodyPreview: true
            )
        )
        let session = makeInterceptingSession(recorder: recorder) { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie": "session=secret"
                ]
            )!
            return (response, Data(#"{"token":"response-secret","ok":true}"#.utf8))
        }
        defer {
            session.invalidateAndCancel()
        }

        var request = URLRequest(
            url: URL(string: "https://example.com/orders?accessToken=secret-token")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer top-secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"clientSecret":"abc123","title":"Preview"}"#.utf8)

        let (data, response) = try await session.data(for: request)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"token":"response-secret","ok":true}"#)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let snapshot = await waitForSnapshotCount(1, recorder: recorder)
        let event = try XCTUnwrap(snapshot.first)

        XCTAssertEqual(event.method, "POST")
        XCTAssertEqual(event.queryItems.first?.value, "<redacted>")
        XCTAssertEqual(event.request.headers.first(where: { $0.name == "Authorization" })?.value, "<redacted>")
        let requestBodyPreview = try XCTUnwrap(event.request.bodyPreview)
        XCTAssertTrue(requestBodyPreview.contains(#""clientSecret":"<redacted>""#))
        XCTAssertTrue(event.response?.bodyPreview?.contains(#""token":"<redacted>""#) == true)
        XCTAssertEqual(event.response?.headers.first(where: { $0.name == "Set-Cookie" })?.value, "<redacted>")
        XCTAssertEqual(StubNetworkURLProtocol.receivedRequests.first?.httpMethod, "POST")
    }

    func testInstalledCaptureUsesPassthroughSessionWithoutRecursiveInterception() async throws {
        let recorder = NetworkRecorder()
        let session = makeInterceptingSession(recorder: recorder) { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer {
            session.invalidateAndCancel()
        }

        let request = URLRequest(url: URL(string: "https://example.com/ping")!)
        _ = try await session.data(for: request)

        let snapshot = await waitForSnapshotCount(1, recorder: recorder)
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(StubNetworkURLProtocol.receivedRequests.count, 1)
        XCTAssertNil(
            StubNetworkURLProtocol.receivedRequests.first?
                .value(forHTTPHeaderField: AppReportNetworkCaptureInternals.captureHeaderName)
        )
    }

    func testInstalledCaptureSkipsAppReportUploadsSentThroughURLSessionTransport() async throws {
        let recorder = NetworkRecorder()
        let session = makeInterceptingSession(recorder: recorder) { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer {
            session.invalidateAndCancel()
        }

        let transport = URLSessionTransport(session: session)
        let request = URLRequest(url: URL(string: "https://reports.example.com/v1/report")!)
        let response = try await transport.send(request: request, body: Data(#"{"ok":true}"#.utf8))

        XCTAssertEqual(response.statusCode, 202)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = await recorder.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(StubNetworkURLProtocol.receivedRequests.count, 1)
        XCTAssertNil(
            StubNetworkURLProtocol.receivedRequests.first?
                .value(forHTTPHeaderField: AppReportNetworkCaptureInternals.captureHeaderName)
        )
    }

    func testBinaryBodiesDoNotProducePreview() async throws {
        let policy = NetworkCapturePolicy(
            capturesRequestBodyPreview: true,
            capturesResponseBodyPreview: true
        )
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        request.httpMethod = "POST"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data([0x89, 0x50, 0x4E, 0x47])

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/octet-stream"]
        )!

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            outcome: .init(
                response: response,
                responseBody: Data([0x00, 0x01, 0x02]),
                completedAt: Date(timeIntervalSince1970: 1)
            )
        )

        let snapshot = await recorder.snapshot()
        let event = try XCTUnwrap(snapshot.first)
        XCTAssertNil(event.request.bodyPreview)
        XCTAssertNil(event.response?.bodyPreview)
    }

    func testBodyPreviewObeysByteLimit() async throws {
        let policy = NetworkCapturePolicy(
            capturesRequestBodyPreview: true,
            limits: .init(maxBodyPreviewBytes: 8)
        )
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(url: URL(string: "https://example.com/export")!)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("abcdefghijklmnop".utf8)

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            outcome: .init(completedAt: Date(timeIntervalSince1970: 1))
        )

        let snapshot = await recorder.snapshot()
        let preview = try XCTUnwrap(snapshot.first?.request.bodyPreview)
        XCTAssertEqual(preview.utf8.count, 8)
    }

    func testTextBodyPreviewScrubsBearerTokens() async throws {
        let policy = NetworkCapturePolicy(capturesRequestBodyPreview: true)
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(url: URL(string: "https://example.com/export")!)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("Authorization: Bearer top-secret-token".utf8)

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            outcome: .init(completedAt: Date(timeIntervalSince1970: 1))
        )

        let snapshot = await recorder.snapshot()
        let preview = try XCTUnwrap(snapshot.first?.request.bodyPreview)
        XCTAssertFalse(preview.contains("top-secret-token"))
        XCTAssertTrue(preview.contains("Bearer <redacted>"))
    }

    func testMalformedJSONPreviewIsDroppedInsteadOfPassingThroughRawText() async throws {
        let policy = NetworkCapturePolicy(capturesRequestBodyPreview: true)
        let recorder = NetworkRecorder(policy: policy)
        var request = URLRequest(url: URL(string: "https://example.com/export")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"token":"top-secret""#.utf8)

        await recorder.record(
            request: request,
            startedAt: Date(timeIntervalSince1970: 0),
            outcome: .init(completedAt: Date(timeIntervalSince1970: 1))
        )

        let snapshot = await recorder.snapshot()
        XCTAssertNil(snapshot.first?.request.bodyPreview)
    }

    func testRollingBufferObeysEventCountAndRetainedBytes() {
        var countLimitedBuffer = NetworkRollingBuffer(maxEventCount: 2, maxRetainedBytes: 500)

        countLimitedBuffer.append(makeEvent(id: "one", bodyPreview: String(repeating: "a", count: 40)))
        countLimitedBuffer.append(makeEvent(id: "two", bodyPreview: String(repeating: "b", count: 40)))
        countLimitedBuffer.append(makeEvent(id: "three", bodyPreview: String(repeating: "c", count: 40)))

        XCTAssertEqual(countLimitedBuffer.snapshot.map(\.id), ["two", "three"])

        var byteLimitedBuffer = NetworkRollingBuffer(maxEventCount: 5, maxRetainedBytes: 90)

        byteLimitedBuffer.append(makeEvent(id: "one", bodyPreview: String(repeating: "a", count: 40)))
        byteLimitedBuffer.append(makeEvent(id: "two", bodyPreview: String(repeating: "b", count: 40)))
        byteLimitedBuffer.append(makeEvent(id: "three", bodyPreview: String(repeating: "c", count: 40)))

        XCTAssertLessThanOrEqual(byteLimitedBuffer.totalRetainedBytes, 90)
        XCTAssertEqual(byteLimitedBuffer.snapshot.map(\.id), ["three"])
    }

    private func makeEvent(id: String, bodyPreview: String) -> NetworkEvent {
        NetworkEvent(
            id: id,
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "GET",
                scheme: "https",
                host: "example.com",
                path: "/events",
                queryItems: []
            ),
            request: .init(
                headers: [],
                bodyPreview: bodyPreview,
                bodySize: bodyPreview.utf8.count,
                mimeType: "text/plain",
                httpVersion: "HTTP/1.1"
            ),
            response: nil,
            failure: nil,
            taskMetadata: [:]
        )
    }

    private func makeInterceptingSession(
        recorder: NetworkRecorder,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        StubNetworkURLProtocol.reset()
        StubNetworkURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubNetworkURLProtocol.self]
        AppReportNetworkCapture.install(on: configuration, recorder: recorder)
        return URLSession(configuration: configuration)
    }

    private func waitForSnapshotCount(
        _ expectedCount: Int,
        recorder: NetworkRecorder
    ) async -> [NetworkEvent] {
        for _ in 0..<20 {
            let snapshot = await recorder.snapshot()
            if snapshot.count == expectedCount {
                return snapshot
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return await recorder.snapshot()
    }
}

private final class StubNetworkURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var storedRequests: [URLRequest] = []

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    static var receivedRequests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    static func reset() {
        lock.withLock {
            _handler = nil
            storedRequests = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self.storedRequests.append(request)
        }

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
