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
    @Published var screenshotPreviews: [FeedbackFormScreenshotPreview]
    @Published var isSubmitting = false
    @Published var isSubmitted = false
    @Published var errorMessage: String?

    private let submitter: any FeedbackSubmitting
    private let deliveryHandler: FeedbackDeliveryHandler?
    private let copy: FeedbackFormCopy
    private let screenContext: String?
    private let supportOptions: FeedbackFormSupportOptions
    private let screenshotProvider: FeedbackScreenshotProviding?
    private let submissionRoute: FeedbackSubmissionRoute
    private let policy: FeedbackFormPolicy
    private let allowedKinds: [FeedbackReportKind]
    private let shouldShowKindPicker: Bool
    private let shouldShowSeverityPicker: Bool
    private let shouldShowTechnicalDetailsToggle: Bool
    private let shouldShowScreenshotToggle: Bool

    init(
        submitter: any FeedbackSubmitting,
        initialKind: FeedbackReportKind,
        copy: FeedbackFormCopy,
        screenContext: String?,
        supportOptions: FeedbackFormSupportOptions,
        policy: FeedbackFormPolicy,
        deliveryHandler: FeedbackDeliveryHandler?
    ) {
        self.submitter = submitter
        allowedKinds = policy.allowedKinds
        kind = Self.resolveInitialKind(
            initialKind: initialKind,
            fallback: policy.defaultKind,
            allowedKinds: allowedKinds
        )
        severity = policy.defaultSeverity
        self.copy = copy
        self.screenContext = screenContext
        self.supportOptions = supportOptions
        self.deliveryHandler = deliveryHandler
        self.policy = policy
        submissionRoute = (submitter as? any FeedbackSubmissionRouteProviding)?.feedbackSubmissionRoute ?? .endpoint
        screenshotProvider = submitter as? FeedbackScreenshotProviding

        shouldShowTechnicalDetailsToggle = supportOptions.allowsTechnicalDetails && policy.allowsTechnicalDetails
        shouldShowScreenshotToggle = supportOptions.allowsScreenshot
            && policy.allowsScreenshot
            && screenshotProvider != nil
        shouldShowKindPicker = policy.showsKindPickerWhenNeeded
        shouldShowSeverityPicker = policy.showsSeverityPicker
        screenshotPreviews = Self.makeScreenshotPreviews(
            using: screenshotProvider,
            enabled: shouldShowScreenshotToggle
        )
        includeTechnicalDetails = shouldShowTechnicalDetailsToggle && policy.technicalDetailsDefaultOn
        includeScreenshot = shouldShowScreenshotToggle && policy.screenshotDefaultOn
    }

    var canSubmit: Bool {
        guard !isSubmitting else {
            return false
        }

        guard !policy.requiresNotes || !trimmedNotes.isEmpty else {
            return false
        }

        if policy.requiresEmail && trimmedEmail.isEmpty {
            return false
        }

        return true
    }

    var submitButtonTitle: String {
        canSubmit ? copy.activeSubmitButtonTitle(for: submissionRoute) : copy.disabledSubmitButtonTitle(for: submissionRoute)
    }

    var showsTechnicalDetailsToggle: Bool {
        shouldShowTechnicalDetailsToggle
    }

    var showsScreenshotToggle: Bool {
        shouldShowScreenshotToggle
    }

    var showsKindPicker: Bool {
        shouldShowKindPicker
    }

    var showsSeverityPicker: Bool {
        shouldShowSeverityPicker
    }

    var showsEmailField: Bool {
        policy.allowsEmail || policy.requiresEmail
    }

    var kindOptions: [FeedbackReportKind] {
        allowedKinds
    }

    var hasScreenshotsForSubmission: Bool {
        !screenshotPreviews.isEmpty
    }

    func removeScreenshot(_ id: FeedbackFormScreenshotPreview.ID) {
        screenshotPreviews.removeAll { $0.id == id }
        if screenshotPreviews.isEmpty {
            includeScreenshot = false
        }
    }

    func removeAllScreenshots() {
        screenshotPreviews.removeAll()
        includeScreenshot = false
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
            let shouldIncludeScreenshot = hasScreenshotsForSubmission && shouldShowScreenshotToggle && includeScreenshot
            let request = FeedbackSubmissionRequest(
                details: .init(
                    kind: kind,
                    notes: notes,
                    severity: severity,
                    email: normalizedEmail,
                    screen: screenContext
                ),
                options: .init(
                    includeTechnicalDetails: shouldShowTechnicalDetailsToggle && includeTechnicalDetails,
                    includeScreenshot: shouldIncludeScreenshot
                ),
                screenshotAttachments: shouldIncludeScreenshot
                    ? Self.makeScreenshotAttachments(from: screenshotPreviews)
                    : []
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

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String? {
        let visibleEmail = showsEmailField ? trimmedEmail : ""
        return visibleEmail.isEmpty ? nil : visibleEmail
    }

    private func markSubmitted() {
        notes = ""
        email = ""
        includeTechnicalDetails = shouldShowTechnicalDetailsToggle && policy.technicalDetailsDefaultOn
        includeScreenshot = shouldShowScreenshotToggle && policy.screenshotDefaultOn
        isSubmitted = true
    }

    private static func resolveInitialKind(
        initialKind: FeedbackReportKind,
        fallback: FeedbackReportKind,
        allowedKinds: [FeedbackReportKind]
    ) -> FeedbackReportKind {
        if allowedKinds.contains(initialKind) {
            return initialKind
        }

        if allowedKinds.contains(fallback) {
            return fallback
        }

        return allowedKinds[0]
    }

    private static func makeScreenshotPreviews(
        using provider: FeedbackScreenshotProviding?,
        enabled: Bool
    ) -> [FeedbackFormScreenshotPreview] {
        guard enabled, let provider else {
            return []
        }

        return (try? provider.makeScreenshots())?
            .compactMap { screenshot in
                FeedbackFormScreenshotPreview(
                    data: screenshot.data,
                    filename: screenshot.filename,
                    contentType: screenshot.contentType
                )
            } ?? []
    }

    private static func makeScreenshotAttachments(
        from previews: [FeedbackFormScreenshotPreview]
    ) -> [FeedbackAttachment] {
        previews.map { preview in
            FeedbackAttachment(
                filename: preview.filename,
                contentType: preview.contentType,
                data: preview.data
            )
        }
    }
}

struct FeedbackFormScreenshotPreview: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let filename: String
    let contentType: String
}
