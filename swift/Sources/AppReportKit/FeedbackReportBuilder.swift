import Foundation

public struct FeedbackReportBuilder {
    private let appId: String
    private let metadataProvider: FeedbackMetadataProviding

    public init(
        appId: String,
        metadataProvider: FeedbackMetadataProviding = SystemFeedbackMetadataProvider()
    ) {
        self.appId = appId
        self.metadataProvider = metadataProvider
    }

    public func makeReport(
        details: FeedbackSubmissionRequest.Details,
        diagnostics: [String: String] = [:],
        attachments: [FeedbackAttachment] = [],
        breadcrumbs: [FeedbackBreadcrumb] = []
    ) -> FeedbackReport {
        FeedbackReport(
            appId: appId,
            kind: details.kind,
            notes: details.notes,
            metadata: metadataProvider.makeMetadata(screen: details.screen),
            submission: .init(
                severity: details.severity,
                email: details.email,
                diagnostics: diagnostics,
                attachments: attachments,
                breadcrumbs: breadcrumbs
            )
        )
    }
}
