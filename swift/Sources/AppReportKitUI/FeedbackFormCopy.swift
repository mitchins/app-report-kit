import Foundation

public struct FeedbackFormCopy: Equatable, Sendable {
    public var reportSectionTitle = "Report"
    public var kindLabel = "Type"
    public var severityLabel = "Severity"
    public var contextLabel = "Context"
    public var notesLabel = "Notes / steps"
    public var notesPlaceholder = "Describe what happened, or what you want to change."
    public var emailPlaceholder = "Email (optional)"
    public var submitButtonTitle = "Send report"
    public var successMessage = "Thanks — your report was queued."
    public var validationErrorMessage = "Please add notes or steps before sending."
    public var submissionErrorMessage = "Unable to send right now."

    public init(configure: (inout FeedbackFormCopy) -> Void = { _ in
        // Intentionally empty: the standard copy uses the stored default values.
    }) {
        configure(&self)
    }

    public static let standard = FeedbackFormCopy()
}
