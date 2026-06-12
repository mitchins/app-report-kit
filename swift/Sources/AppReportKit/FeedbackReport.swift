import Foundation

public struct FeedbackReport: Codable, Equatable {
    public struct SubmissionContext: Equatable {
        public let severity: FeedbackSeverity
        public let email: String?
        public let diagnostics: [String: String]
        public let attachments: [FeedbackAttachment]
        public let breadcrumbs: [FeedbackBreadcrumb]

        public init(
            severity: FeedbackSeverity = .normal,
            email: String? = nil,
            diagnostics: [String: String] = [:],
            attachments: [FeedbackAttachment] = [],
            breadcrumbs: [FeedbackBreadcrumb] = []
        ) {
            self.severity = severity
            self.email = email
            self.diagnostics = diagnostics
            self.attachments = attachments
            self.breadcrumbs = breadcrumbs
        }
    }

    public let appId: String
    public let kind: FeedbackReportKind
    public let severity: FeedbackSeverity
    public let notes: String
    public let email: String?
    public let metadata: FeedbackMetadata
    public let diagnostics: [String: String]?
    public let attachments: [FeedbackAttachment]
    public let breadcrumbs: [FeedbackBreadcrumb]

    public init(
        appId: String,
        kind: FeedbackReportKind,
        notes: String,
        metadata: FeedbackMetadata,
        submission: SubmissionContext = .init()
    ) {
        self.appId = appId
        self.kind = kind
        severity = submission.severity
        self.notes = notes
        email = submission.email?.nilIfBlank
        self.metadata = metadata
        diagnostics = submission.diagnostics.isEmpty ? nil : submission.diagnostics
        attachments = submission.attachments
        breadcrumbs = submission.breadcrumbs
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
