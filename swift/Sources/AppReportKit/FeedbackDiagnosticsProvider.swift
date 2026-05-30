import Foundation

public protocol FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String]
}

public struct EmptyFeedbackDiagnosticsProvider: FeedbackDiagnosticsProvider {
    public init() {
        // Intentionally empty: the default provider exposes no extra diagnostics.
    }

    public func makeDiagnostics() -> [String: String] {
        // The default provider intentionally emits no diagnostics so host apps
        // opt in explicitly to any additional context they want to disclose.
        [:]
    }
}
