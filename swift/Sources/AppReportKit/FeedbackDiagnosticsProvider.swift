import Foundation

public protocol FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String]
}

public struct EmptyFeedbackDiagnosticsProvider: FeedbackDiagnosticsProvider {
    public init() {}

    public func makeDiagnostics() -> [String: String] {
        // The default provider intentionally emits no diagnostics so host apps
        // opt in explicitly to any additional context they want to disclose.
        [:]
    }
}
