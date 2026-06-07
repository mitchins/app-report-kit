import Foundation

public struct NetworkCapturePolicy: Equatable, Sendable {
    public let capturesRequestHeaders: Bool
    public let capturesResponseHeaders: Bool
    public let capturesRequestBodyPreview: Bool
    public let capturesResponseBodyPreview: Bool
    public let maxEventCount: Int
    public let maxRetainedBytes: Int
    public let maxBodyPreviewBytes: Int
    public let redactedKeys: Set<String>

    public init(
        capturesRequestHeaders: Bool = true,
        capturesResponseHeaders: Bool = true,
        capturesRequestBodyPreview: Bool = false,
        capturesResponseBodyPreview: Bool = false,
        maxEventCount: Int = 100,
        maxRetainedBytes: Int = 256 * 1024,
        maxBodyPreviewBytes: Int = 1024,
        redactedKeys: [String] = Self.defaultRedactedKeys
    ) {
        self.capturesRequestHeaders = capturesRequestHeaders
        self.capturesResponseHeaders = capturesResponseHeaders
        self.capturesRequestBodyPreview = capturesRequestBodyPreview
        self.capturesResponseBodyPreview = capturesResponseBodyPreview
        self.maxEventCount = maxEventCount
        self.maxRetainedBytes = maxRetainedBytes
        self.maxBodyPreviewBytes = maxBodyPreviewBytes
        self.redactedKeys = Set(redactedKeys.map { $0.lowercased() })
    }

    public static let metadataOnly = NetworkCapturePolicy()

    public static let defaultRedactedKeys = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "api-key",
        "api_key",
        "auth_token",
        "token",
        "access_token",
        "refresh_token",
        "id_token",
        "password",
        "passcode",
        "secret",
        "client_secret",
        "session",
        "session_id",
        "jwt",
        "bearer",
        "csrf",
        "xsrf"
    ]
}
