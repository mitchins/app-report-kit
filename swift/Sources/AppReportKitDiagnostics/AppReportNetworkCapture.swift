import AppReportKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AppReportNetworkCapture {
    public static func install(
        on configuration: URLSessionConfiguration,
        recorder: NetworkRecorder
    ) {
        let existingCaptureID = AppReportNetworkCaptureInternals.captureID(
            from: configuration.httpAdditionalHeaders
        )
        let captureID = UUID().uuidString

        AppReportNetworkCaptureContextRegistry.shared.install(
            captureID: captureID,
            recorder: recorder,
            configuration: configuration
        )
        if let existingCaptureID {
            AppReportNetworkCaptureContextRegistry.shared.remove(captureID: existingCaptureID)
        }

        configuration.httpAdditionalHeaders = AppReportNetworkCaptureInternals
            .settingHeader(
                named: AppReportNetworkCaptureInternals.captureHeaderName,
                value: captureID,
                in: configuration.httpAdditionalHeaders
            )

        var protocolClasses = configuration.protocolClasses ?? []
        if !protocolClasses.contains(where: { $0 == AppReportCaptureURLProtocol.self }) {
            protocolClasses.insert(AppReportCaptureURLProtocol.self, at: 0)
            configuration.protocolClasses = protocolClasses
        }
    }
}

enum AppReportNetworkCaptureInternals {
    static let captureHeaderName = "X-AppReportKit-Capture-ID"
    static let handledRequestPropertyKey = "com.appreportkit.diagnostics.capture.handled"

    static func captureID(from request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: captureHeaderName)
    }

    static func captureID(from headers: [AnyHashable: Any]?) -> String? {
        headers?.first { entry in
            String(describing: entry.key).caseInsensitiveCompare(captureHeaderName) == .orderedSame
        }
        .map { String(describing: $0.value) }
    }

    static func settingHeader(
        named name: String,
        value: String?,
        in headers: [AnyHashable: Any]?
    ) -> [AnyHashable: Any]? {
        var updatedHeaders = headers ?? [:]
        for key in updatedHeaders.keys {
            if String(describing: key).caseInsensitiveCompare(name) == .orderedSame {
                updatedHeaders.removeValue(forKey: key)
            }
        }

        if let value {
            updatedHeaders[name] = value
        }

        return updatedHeaders.isEmpty ? nil : updatedHeaders
    }

    static func isHandled(_ request: URLRequest) -> Bool {
        (URLProtocol.property(forKey: handledRequestPropertyKey, in: request) as? Bool) == true
    }

    static func markingHandled(_ request: URLRequest) -> URLRequest {
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: handledRequestPropertyKey, in: mutableRequest)
        return mutableRequest as URLRequest
    }

    static func strippingInternalCaptureState(from request: URLRequest) -> URLRequest {
        var sanitizedRequest = request
        sanitizedRequest.setValue(nil, forHTTPHeaderField: captureHeaderName)
        return markingHandled(sanitizedRequest)
    }
}

private final class AppReportNetworkCaptureContextRegistry {
    static let shared = AppReportNetworkCaptureContextRegistry()

    private let lock = NSLock()
    private var contexts: [String: AppReportNetworkCaptureContext] = [:]

    func install(
        captureID: String,
        recorder: NetworkRecorder,
        configuration: URLSessionConfiguration
    ) {
        lock.withLock {
            contexts[captureID] = AppReportNetworkCaptureContext(
                recorder: recorder,
                baseConfiguration: configuration
            )
        }
    }

    func context(for captureID: String) -> AppReportNetworkCaptureContext? {
        lock.withLock { contexts[captureID] }
    }

    func remove(captureID: String) {
        _ = lock.withLock {
            contexts.removeValue(forKey: captureID)
        }
    }
}

private final class AppReportNetworkCaptureContext {
    let recorder: NetworkRecorder

    private let lock = NSLock()
    private let baseConfiguration: URLSessionConfiguration

    init(recorder: NetworkRecorder, baseConfiguration: URLSessionConfiguration) {
        self.recorder = recorder
        self.baseConfiguration = baseConfiguration
    }

    func makePassthroughConfiguration() -> URLSessionConfiguration {
        lock.withLock {
            let configurationCopy = baseConfiguration.copy() as! URLSessionConfiguration
            configurationCopy.protocolClasses = (configurationCopy.protocolClasses ?? []).filter {
                $0 != AppReportCaptureURLProtocol.self
            }
            configurationCopy.httpAdditionalHeaders = AppReportNetworkCaptureInternals
                .settingHeader(
                    named: AppReportNetworkCaptureInternals.captureHeaderName,
                    value: nil,
                    in: configurationCopy.httpAdditionalHeaders
                )
            return configurationCopy
        }
    }
}

final class AppReportCaptureURLProtocol: URLProtocol {
    private var shouldRecord = true
    private var startedAt: Date?
    private var accumulatedData = Data()
    private var response: HTTPURLResponse?
    private var httpVersion: String?
    private var passthroughRequest: URLRequest?
    private var requestBody: Data?
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard
            let scheme = request.url?.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return false
        }

        guard !AppReportNetworkCaptureInternals.isHandled(request) else {
            return false
        }

        guard
            let captureID = AppReportNetworkCaptureInternals.captureID(from: request),
            AppReportNetworkCaptureContextRegistry.shared.context(for: captureID) != nil
        else {
            return false
        }

        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        shouldRecord = !AppReportCaptureControl.isExcludedFromDiagnosticsCapture(request)

        guard
            let captureID = AppReportNetworkCaptureInternals.captureID(from: request),
            let captureContext = AppReportNetworkCaptureContextRegistry.shared.context(for: captureID)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        startedAt = Date()
        requestBody = Self.captureRequestBody(from: request)

        var sanitizedRequest = AppReportNetworkCaptureInternals
            .strippingInternalCaptureState(from: request)
        if let requestBody {
            sanitizedRequest.httpBodyStream = nil
            sanitizedRequest.httpBody = requestBody
        }
        passthroughRequest = sanitizedRequest

        let passthroughSession = URLSession(
            configuration: captureContext.makePassthroughConfiguration(),
            delegate: self,
            delegateQueue: nil
        )
        session = passthroughSession

        let task = passthroughSession.dataTask(with: passthroughRequest ?? request)
        dataTask = task
        task.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session?.invalidateAndCancel()
        dataTask = nil
        session = nil
    }

    private static func captureRequestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        return readBodyStream(bodyStream)
    }

    private static func readBodyStream(_ bodyStream: InputStream) -> Data? {
        bodyStream.open()
        defer {
            bodyStream.close()
        }

        var body = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(buffer, maxLength: bufferSize)
            guard bytesRead >= 0 else {
                return nil
            }
            guard bytesRead > 0 else {
                break
            }
            body.append(buffer, count: bytesRead)
        }

        return body.isEmpty ? nil : body
    }
}

extension AppReportCaptureURLProtocol: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        accumulatedData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(
        _ session: URLSession,
        task _: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        httpVersion = metrics.transactionMetrics.last.flatMap { metric in
            HTTPVersionResolver.resolve(from: metric.networkProtocolName)
        }
    }

    func urlSession(
        _ session: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }

        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
            dataTask = nil
        }

        guard
            let captureID = AppReportNetworkCaptureInternals.captureID(from: request),
            let captureContext = AppReportNetworkCaptureContextRegistry.shared.context(for: captureID),
            let startedAt,
            let passthroughRequest
        else {
            return
        }

        guard shouldRecord else {
            return
        }

        Task {
            await captureContext.recorder.record(
                request: passthroughRequest,
                startedAt: startedAt,
                context: .init(
                    requestBody: requestBody,
                    requestHTTPVersion: httpVersion
                ),
                outcome: .init(
                    response: response,
                    responseBody: accumulatedData,
                    error: error,
                    completedAt: Date(),
                    responseHTTPVersion: httpVersion
                )
            )
        }
    }
}
