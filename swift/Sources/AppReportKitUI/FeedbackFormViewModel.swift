import AppReportKit
import Foundation
import SwiftUI

public typealias FeedbackDeliveryHandler = @MainActor (FeedbackPendingDelivery) async -> Bool

@MainActor
final class FeedbackFormViewModel: ObservableObject {
    @Published var kind: FeedbackReportKind
    @Published var severity: FeedbackSeverity
    @Published var notes = ""
    @Published var email = ""
    @Published var includeTechnicalDetails: Bool
    @Published var includeScreenshot: Bool
    @Published var isSubmitting = false
    @Published var isSubmitted = false
    @Published var errorMessage: String?

    private let submitter: any FeedbackSubmitting
    private let deliveryHandler: FeedbackDeliveryHandler?
    private let copy: FeedbackFormCopy
    private let screenContext: String?
    private let supportOptions: FeedbackFormSupportOptions

    init(
        submitter: any FeedbackSubmitting,
        initialKind: FeedbackReportKind,
        copy: FeedbackFormCopy,
        screenContext: String?,
        supportOptions: FeedbackFormSupportOptions,
        deliveryHandler: FeedbackDeliveryHandler?
    ) {
        self.submitter = submitter
        self.kind = initialKind
        self.severity = .normal
        self.copy = copy
        self.screenContext = screenContext
        self.supportOptions = supportOptions
        includeTechnicalDetails = supportOptions.technicalDetailsEnabledByDefault
        includeScreenshot = supportOptions.screenshotEnabledByDefault
        self.deliveryHandler = deliveryHandler
    }

    var canSubmit: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var showsTechnicalDetailsToggle: Bool {
        supportOptions.allowsTechnicalDetails
    }

    var showsScreenshotToggle: Bool {
        supportOptions.allowsScreenshot
    }

    func submit() async {
        guard canSubmit else {
            errorMessage = copy.validationErrorMessage
            return
        }

        isSubmitting = true
        errorMessage = nil
        isSubmitted = false
        defer { isSubmitting = false }

        do {
            let request = FeedbackSubmissionRequest(
                kind: kind,
                notes: notes,
                severity: severity,
                email: email,
                screen: screenContext,
                options: .init(
                    includeTechnicalDetails: showsTechnicalDetailsToggle && includeTechnicalDetails,
                    includeScreenshot: showsScreenshotToggle && includeScreenshot
                )
            )

            let outcome = try await submitter.submit(request)
            switch outcome {
            case .submitted:
                markSubmitted()
            case let .needsUserAction(pendingDelivery):
                guard let deliveryHandler else {
                    errorMessage = copy.submissionErrorMessage
                    return
                }

                let completed = await deliveryHandler(pendingDelivery)
                guard completed else {
                    return
                }

                markSubmitted()
            }
        } catch AppReportClientError.emptyNotes {
            errorMessage = copy.validationErrorMessage
        } catch {
            errorMessage = copy.submissionErrorMessage
        }
    }

    private func markSubmitted() {
        notes = ""
        email = ""
        includeTechnicalDetails = supportOptions.technicalDetailsEnabledByDefault
        includeScreenshot = supportOptions.screenshotEnabledByDefault
        isSubmitted = true
    }
}
