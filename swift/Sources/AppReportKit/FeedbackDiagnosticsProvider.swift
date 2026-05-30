import Foundation

public protocol FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String]
}

public struct EmptyFeedbackDiagnosticsProvider: FeedbackDiagnosticsProvider {
    public init() {}

    public func makeDiagnostics() -> [String: String] {
        [:]
    }
}

