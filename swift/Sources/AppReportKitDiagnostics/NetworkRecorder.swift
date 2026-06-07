import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum HTTPVersionResolver {
    static func resolve(from networkProtocolName: String?) -> String? {
        guard
            let normalized = networkProtocolName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            !normalized.isEmpty
        else {
            return nil
        }

        switch normalized {
        case "h2", "http/2", "http2":
            return "HTTP/2"
        case "h3", "http/3", "http3":
            return "HTTP/3"
        case "http/1.1", "http1.1", "http11":
            return "HTTP/1.1"
        case "http/1.0", "http1.0", "http10":
            return "HTTP/1.0"
        default:
            guard normalized.hasPrefix("http/") else {
                return nil
            }
            return normalized.uppercased()
        }
    }
}

public actor NetworkRecorder {
    public struct RecordContext: Sendable {
        public let requestBody: Data?
        public let taskMetadata: [String: String]
        public let requestHTTPVersion: String?

        public init(
            requestBody: Data? = nil,
            taskMetadata: [String: String] = [:],
            requestHTTPVersion: String? = nil
        ) {
            self.requestBody = requestBody
            self.taskMetadata = taskMetadata
            self.requestHTTPVersion = requestHTTPVersion
        }
    }

    public struct RecordOutcome: Sendable {
        public let response: HTTPURLResponse?
        public let responseBody: Data?
        public let error: Error?
        public let completedAt: Date?
        public let responseHTTPVersion: String?

        public init(
            response: HTTPURLResponse? = nil,
            responseBody: Data? = nil,
            error: Error? = nil,
            completedAt: Date? = nil,
            responseHTTPVersion: String? = nil
        ) {
            self.response = response
            self.responseBody = responseBody
            self.error = error
            self.completedAt = completedAt
            self.responseHTTPVersion = responseHTTPVersion
        }
    }

    private let policy: NetworkCapturePolicy
    private let redactor: NetworkRedactor
    private let idProvider: @Sendable () -> String
    private var rollingBuffer: NetworkRollingBuffer
    private static let rootPath = NSString.path(withComponents: ["", ""])

    public init(
        policy: NetworkCapturePolicy = .metadataOnly,
        idProvider: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.policy = policy
        redactor = NetworkRedactor(policy: policy)
        self.idProvider = idProvider
        rollingBuffer = NetworkRollingBuffer(
            maxEventCount: policy.maxEventCount,
            maxRetainedBytes: policy.maxRetainedBytes
        )
    }

    public nonisolated var capturePolicy: NetworkCapturePolicy {
        policy
    }

    public func capture(
        request: URLRequest,
        taskMetadata: [String: String] = [:],
        operation: @Sendable () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        let startedAt = Date()

        do {
            let (data, response) = try await operation()
            record(
                request: request,
                startedAt: startedAt,
                context: .init(taskMetadata: taskMetadata),
                outcome: .init(
                    response: response as? HTTPURLResponse,
                    responseBody: data,
                    completedAt: Date()
                )
            )
            return (data, response)
        } catch {
            record(
                request: request,
                startedAt: startedAt,
                context: .init(taskMetadata: taskMetadata),
                outcome: .init(
                    error: error,
                    completedAt: Date()
                )
            )
            throw error
        }
    }

    public func record(
        request: URLRequest,
        startedAt: Date,
        context: RecordContext = .init(),
        outcome: RecordOutcome = .init()
    ) {
        let url = request.url ?? URL(string: "about:blank")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let requestHeaders = policy.capturesRequestHeaders ? redactor.redactHeaders(request.allHTTPHeaderFields) : []
        let responseHeaders = policy.capturesResponseHeaders ? redactor.redactHeaders(outcome.response?.allHeaderFields) : []
        let requestContentType = request.value(forHTTPHeaderField: "Content-Type")
        let responseContentType = outcome.response?.value(forHTTPHeaderField: "Content-Type")
        let effectiveRequestBody = context.requestBody ?? request.httpBody
        let requestPreview = redactor.bodyPreview(
            from: effectiveRequestBody,
            contentType: requestContentType,
            enabled: policy.capturesRequestBodyPreview
        )
        let responsePreview = redactor.bodyPreview(
            from: outcome.responseBody,
            contentType: responseContentType,
            enabled: policy.capturesResponseBodyPreview
        )
        let failure = outcome.error.map { error in
            let nsError = error as NSError
            return NetworkEvent.FailureDetails(
                domain: nsError.domain,
                code: nsError.code,
                description: nsError.localizedDescription
            )
        }
        let durationMs = outcome.completedAt.map { $0.timeIntervalSince(startedAt) * 1000 }

        let event = NetworkEvent(
            id: idProvider(),
            timing: .init(
                startedAt: startedAt,
                completedAt: outcome.completedAt,
                durationMs: durationMs
            ),
            target: .init(
                method: request.httpMethod ?? "GET",
                scheme: components?.scheme ?? "",
                host: components?.host ?? "",
                path: components?.path.isEmpty == false ? (components?.path ?? "") : Self.rootPath,
                queryItems: redactor.redactQueryItems(components?.queryItems ?? [])
            ),
            request: .init(
                headers: requestHeaders,
                bodyPreview: requestPreview,
                bodySize: effectiveRequestBody?.count,
                mimeType: requestContentType,
                httpVersion: context.requestHTTPVersion
            ),
            response: outcome.response.map { response in
                NetworkEvent.ResponseDetails(
                    statusCode: response.statusCode,
                    statusText: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                    headers: responseHeaders,
                    content: .init(
                        bodyPreview: responsePreview,
                        bodySize: outcome.responseBody?.count,
                        mimeType: responseContentType
                    ),
                    httpVersion: outcome.responseHTTPVersion,
                    redirectURL: response.value(forHTTPHeaderField: "Location")
                )
            },
            failure: failure,
            taskMetadata: redactor.redactMetadata(context.taskMetadata)
        )

        rollingBuffer.append(event)
    }

    public func snapshot() -> [NetworkEvent] {
        rollingBuffer.snapshot
    }

    public func removeAll() {
        rollingBuffer.removeAll()
    }
}

public struct InstrumentedURLSession {
    private let session: URLSession
    private let recorder: NetworkRecorder

    public init(session: URLSession, recorder: NetworkRecorder) {
        self.session = session
        self.recorder = recorder
    }

    public func data(
        for request: URLRequest,
        taskMetadata: [String: String] = [:]
    ) async throws -> (Data, URLResponse) {
        let startedAt = Date()
        let metricsCollector = TaskMetricsCollector()

        do {
            let (data, response) = try await session.data(for: request, delegate: metricsCollector)
            let httpVersion = metricsCollector.httpVersion
            await recorder.record(
                request: request,
                startedAt: startedAt,
                context: .init(
                    taskMetadata: taskMetadata,
                    requestHTTPVersion: httpVersion
                ),
                outcome: .init(
                    response: response as? HTTPURLResponse,
                    responseBody: data,
                    completedAt: Date(),
                    responseHTTPVersion: httpVersion
                )
            )
            return (data, response)
        } catch {
            await recorder.record(
                request: request,
                startedAt: startedAt,
                context: .init(
                    taskMetadata: taskMetadata,
                    requestHTTPVersion: metricsCollector.httpVersion
                ),
                outcome: .init(
                    error: error,
                    completedAt: Date()
                )
            )
            throw error
        }
    }
}

private final class TaskMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var resolvedHTTPVersion: String?

    var httpVersion: String? {
        lock.withLock { resolvedHTTPVersion }
    }

    func urlSession(
        _ _: URLSession,
        task _: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let version = metrics.transactionMetrics.last.flatMap { metric in
            HTTPVersionResolver.resolve(from: metric.networkProtocolName)
        }
        lock.withLock {
            resolvedHTTPVersion = version
        }
    }
}
