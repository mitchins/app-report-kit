import Foundation

public enum FeedbackReportKind: String, Codable, CaseIterable, Sendable {
    case bug
    case feature
    case feedback
}
