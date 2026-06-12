import Foundation
import AppReportKit

public struct FeedbackFormCopy: Equatable, Sendable {
    public var reportSectionTitle = "Report"
    public var kindLabel = "Type"
    public var severityLabel = "Severity"
    public var contextLabel = "Context"
    public var notesLabel = "Notes / steps"
    public var notesPlaceholder = "Describe what happened, or what you want to change."
    public var emailPlaceholder = "Email (optional)"
    public var includeTechnicalDetailsLabel = "Include technical details to help diagnose the problem"
    public var includeScreenshotLabel = "Attach screenshot"
    public var submitButtonTitle = "Send report"
    public var emailSubmitButtonTitle = "Email report"
    public var shareSubmitButtonTitle = "Share report"
    public var exportSubmitButtonTitle = "Export report"
    public var unavailableSubmitButtonTitle = "Export report"
    public var submitButtonDisabledTitle = "Add notes to send"
    public var emailSubmitButtonDisabledTitle = "Add notes to email"
    public var shareSubmitButtonDisabledTitle = "Add notes to share"
    public var exportSubmitButtonDisabledTitle = "Add notes to export"
    public var unavailableSubmitButtonDisabledTitle = "Add notes to export"
    public var successMessage = "Thanks — your report was queued."
    public var validationErrorMessage = "Please add notes or steps before sending."
    public var submissionErrorMessage = "Unable to send right now."

    public static let issue = FeedbackFormCopy {
        $0.reportSectionTitle = "Report a Problem"
        $0.notesLabel = "What's the issue?"
        $0.notesPlaceholder = "Tell us what happened"
    }

    public static let improvement = FeedbackFormCopy {
        $0.reportSectionTitle = "Report a Problem"
        $0.notesLabel = "Suggest an improvement"
        $0.notesPlaceholder = "Tell us what you'd like to see improved"
    }

    public init(configure: (inout FeedbackFormCopy) -> Void = { _ in
        // Intentionally empty: the standard copy uses the stored default values.
    }) {
        configure(&self)
    }

    public func activeSubmitButtonTitle(for route: FeedbackSubmissionRoute) -> String {
        switch route {
        case .endpoint:
            submitButtonTitle
        case .email:
            emailSubmitButtonTitle
        case .share:
            shareSubmitButtonTitle
        case .export:
            exportSubmitButtonTitle
        case .unavailable:
            unavailableSubmitButtonTitle
        }
    }

    public func disabledSubmitButtonTitle(for route: FeedbackSubmissionRoute) -> String {
        switch route {
        case .endpoint:
            submitButtonDisabledTitle
        case .email:
            emailSubmitButtonDisabledTitle
        case .share:
            shareSubmitButtonDisabledTitle
        case .export:
            exportSubmitButtonDisabledTitle
        case .unavailable:
            unavailableSubmitButtonDisabledTitle
        }
    }

    public static let standard = FeedbackFormCopy()
}
