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
        kind: FeedbackReportKind,
        notes: String,
        severity: FeedbackSeverity = .normal,
        email: String? = nil,
        screen: String? = nil,
        diagnostics: [String: String] = [:],
        attachments: [FeedbackAttachment] = [],
        breadcrumbs: [FeedbackBreadcrumb] = []
    ) -> FeedbackReport {
        FeedbackReport(
            appId: appId,
            kind: kind,
            notes: notes,
            metadata: metadataProvider.makeMetadata(screen: screen),
            submission: .init(
                severity: severity,
                email: email,
                diagnostics: diagnostics,
                attachments: attachments,
                breadcrumbs: breadcrumbs
            )
        )
    }
}
