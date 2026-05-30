import Foundation

public struct FeedbackReport: Codable, Equatable {
    public let appId: String
    public let kind: FeedbackReportKind
    public let severity: FeedbackSeverity
    public let notes: String
    public let email: String?
    public let metadata: FeedbackMetadata
    public let diagnostics: [String: String]?
    public let attachments: [FeedbackAttachment]

    public init(
        appId: String,
        kind: FeedbackReportKind,
        severity: FeedbackSeverity = .normal,
        notes: String,
        email: String? = nil,
        metadata: FeedbackMetadata,
        diagnostics: [String: String] = [:],
        attachments: [FeedbackAttachment] = []
    ) {
        self.appId = appId
        self.kind = kind
        self.severity = severity
        self.notes = notes
        self.email = email?.nilIfBlank
        self.metadata = metadata
        self.diagnostics = diagnostics.isEmpty ? nil : diagnostics
        self.attachments = attachments
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

