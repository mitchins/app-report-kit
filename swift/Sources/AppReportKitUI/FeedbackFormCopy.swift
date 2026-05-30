import Foundation

public struct FeedbackFormCopy: Equatable, Sendable {
    public var reportSectionTitle: String
    public var kindLabel: String
    public var severityLabel: String
    public var contextLabel: String
    public var notesLabel: String
    public var notesPlaceholder: String
    public var emailPlaceholder: String
    public var submitButtonTitle: String
    public var successMessage: String
    public var validationErrorMessage: String
    public var submissionErrorMessage: String

    public init(
        reportSectionTitle: String = "Report",
        kindLabel: String = "Type",
        severityLabel: String = "Severity",
        contextLabel: String = "Context",
        notesLabel: String = "Notes / steps",
        notesPlaceholder: String = "Describe what happened, or what you want to change.",
        emailPlaceholder: String = "Email (optional)",
        submitButtonTitle: String = "Send report",
        successMessage: String = "Thanks — your report was queued.",
        validationErrorMessage: String = "Please add notes or steps before sending.",
        submissionErrorMessage: String = "Unable to send right now."
    ) {
        self.reportSectionTitle = reportSectionTitle
        self.kindLabel = kindLabel
        self.severityLabel = severityLabel
        self.contextLabel = contextLabel
        self.notesLabel = notesLabel
        self.notesPlaceholder = notesPlaceholder
        self.emailPlaceholder = emailPlaceholder
        self.submitButtonTitle = submitButtonTitle
        self.successMessage = successMessage
        self.validationErrorMessage = validationErrorMessage
        self.submissionErrorMessage = submissionErrorMessage
    }

    public static let `default` = FeedbackFormCopy()
}

