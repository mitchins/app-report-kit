import Foundation

public struct NetworkNameValuePair: Codable, Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct NetworkEvent: Codable, Equatable, Sendable {
    public struct RequestDetails: Codable, Equatable, Sendable {
        public let headers: [NetworkNameValuePair]
        public let bodyPreview: String?
        public let bodySize: Int?
        public let mimeType: String?
        public let httpVersion: String?

        public init(
            headers: [NetworkNameValuePair],
            bodyPreview: String?,
            bodySize: Int?,
            mimeType: String?,
            httpVersion: String?
        ) {
            self.headers = headers
            self.bodyPreview = bodyPreview
            self.bodySize = bodySize
            self.mimeType = mimeType
            self.httpVersion = httpVersion
        }
    }

    public struct ResponseDetails: Codable, Equatable, Sendable {
        public struct ContentDetails: Codable, Equatable, Sendable {
            public let bodyPreview: String?
            public let bodySize: Int?
            public let mimeType: String?

            public init(
                bodyPreview: String? = nil,
                bodySize: Int? = nil,
                mimeType: String? = nil
            ) {
                self.bodyPreview = bodyPreview
                self.bodySize = bodySize
                self.mimeType = mimeType
            }
        }

        public let statusCode: Int?
        public let statusText: String
        public let headers: [NetworkNameValuePair]
        public let bodyPreview: String?
        public let bodySize: Int?
        public let mimeType: String?
        public let httpVersion: String?
        public let redirectURL: String?

        public init(
            statusCode: Int?,
            statusText: String,
            headers: [NetworkNameValuePair],
            content: ContentDetails = .init(),
            httpVersion: String?,
            redirectURL: String?
        ) {
            self.statusCode = statusCode
            self.statusText = statusText
            self.headers = headers
            bodyPreview = content.bodyPreview
            bodySize = content.bodySize
            mimeType = content.mimeType
            self.httpVersion = httpVersion
            self.redirectURL = redirectURL
        }
    }

    public struct TimingDetails: Codable, Equatable, Sendable {
        public let startedAt: Date
        public let completedAt: Date?
        public let durationMs: Double?

        public init(
            startedAt: Date,
            completedAt: Date? = nil,
            durationMs: Double? = nil
        ) {
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationMs = durationMs
        }
    }

    public struct TargetDetails: Codable, Equatable, Sendable {
        public let method: String
        public let scheme: String
        public let host: String
        public let path: String
        public let queryItems: [NetworkNameValuePair]

        public init(
            method: String,
            scheme: String,
            host: String,
            path: String,
            queryItems: [NetworkNameValuePair]
        ) {
            self.method = method
            self.scheme = scheme
            self.host = host
            self.path = path
            self.queryItems = queryItems
        }
    }

    public struct FailureDetails: Codable, Equatable, Sendable {
        public let domain: String
        public let code: Int
        public let description: String

        public init(domain: String, code: Int, description: String) {
            self.domain = domain
            self.code = code
            self.description = description
        }
    }

    public let id: String
    public let startedAt: Date
    public let completedAt: Date?
    public let durationMs: Double?
    public let method: String
    public let scheme: String
    public let host: String
    public let path: String
    public let queryItems: [NetworkNameValuePair]
    public let request: RequestDetails
    public let response: ResponseDetails?
    public let failure: FailureDetails?
    public let taskMetadata: [String: String]

    public init(
        id: String,
        timing: TimingDetails,
        target: TargetDetails,
        request: RequestDetails,
        response: ResponseDetails?,
        failure: FailureDetails?,
        taskMetadata: [String: String]
    ) {
        self.id = id
        startedAt = timing.startedAt
        completedAt = timing.completedAt
        durationMs = timing.durationMs
        method = target.method
        scheme = target.scheme
        host = target.host
        path = target.path
        queryItems = target.queryItems
        self.request = request
        self.response = response
        self.failure = failure
        self.taskMetadata = taskMetadata
    }

    public var redactedURLString: String {
        var components = URLComponents()
        components.scheme = scheme.isEmpty ? nil : scheme
        components.host = host.isEmpty ? nil : host
        components.path = path
        components.queryItems = queryItems.map { URLQueryItem(name: $0.name, value: $0.value) }
        return components.string ?? path
    }

    var estimatedByteCount: Int {
        var total = method.utf8.count + scheme.utf8.count + host.utf8.count + path.utf8.count
        total += id.utf8.count

        for item in queryItems {
            total += item.name.utf8.count + item.value.utf8.count
        }

        for header in request.headers {
            total += header.name.utf8.count + header.value.utf8.count
        }

        total += request.bodyPreview?.utf8.count ?? 0

        if let response {
            total += response.statusText.utf8.count
            total += response.bodyPreview?.utf8.count ?? 0
            total += response.mimeType?.utf8.count ?? 0
            total += response.redirectURL?.utf8.count ?? 0
            for header in response.headers {
                total += header.name.utf8.count + header.value.utf8.count
            }
        }

        if let failure {
            total += failure.domain.utf8.count + failure.description.utf8.count + 16
        }

        for (key, value) in taskMetadata {
            total += key.utf8.count + value.utf8.count
        }

        return total
    }
}
