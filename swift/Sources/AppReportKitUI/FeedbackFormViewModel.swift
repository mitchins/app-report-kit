import AppReportKit
import Foundation
import SwiftUI

@MainActor
final class FeedbackFormViewModel: ObservableObject {
    @Published var kind: FeedbackReportKind
    @Published var severity: FeedbackSeverity
    @Published var notes = ""
    @Published var email = ""
    @Published var isSubmitting = false
    @Published var isSubmitted = false
    @Published var errorMessage: String?

    private let client: AppReportClient
    private let copy: FeedbackFormCopy
    private let screenContext: String?

    init(
        client: AppReportClient,
        initialKind: FeedbackReportKind,
        copy: FeedbackFormCopy,
        screenContext: String?
    ) {
        self.client = client
        self.kind = initialKind
        self.severity = .normal
        self.copy = copy
        self.screenContext = screenContext
    }

    var canSubmit: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
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
            _ = try await client.submit(
                kind: kind,
                notes: notes,
                severity: severity,
                email: email,
                screen: screenContext
            )
            notes = ""
            email = ""
            isSubmitted = true
        } catch AppReportClientError.emptyNotes {
            errorMessage = copy.validationErrorMessage
        } catch {
            errorMessage = copy.submissionErrorMessage
        }
    }
}
