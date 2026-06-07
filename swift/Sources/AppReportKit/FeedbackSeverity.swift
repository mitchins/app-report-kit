import Foundation

public enum FeedbackSeverity: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case high
}
