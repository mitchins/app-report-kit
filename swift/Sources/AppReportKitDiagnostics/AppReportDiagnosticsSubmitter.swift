import AppReportKit
import Foundation

#if canImport(MessageUI)
import MessageUI
#endif

public struct EmailFallbackPolicy: Equatable, Sendable {
    public let allowWhenEndpointFails: Bool

    public init(
        allowWhenEndpointFails: Bool = false
    ) {
        self.allowWhenEndpointFails = allowWhenEndpointFails
    }
}

public struct AppReportEmailConfiguration: Sendable {
    public let recipients: [String]
    public let appName: String
    public let subjectProvider: @Sendable (FeedbackReport) -> String
    public let bodyProvider: @Sendable (FeedbackReport, Bool) -> String

    public init(
        recipients: [String],
        appName: String,
        subjectProvider: @escaping @Sendable (FeedbackReport) -> String = { report in
            "\(report.appId) Report"
        },
        bodyProvider: @escaping @Sendable (FeedbackReport, Bool) -> String = { report, includesDiagnostics in
            let metadata = report.metadata
            let attachmentLine = includesDiagnostics
                ? "Diagnostics are attached when available."
                : "No diagnostics attachment was included."
            var bodyLines = [
                "Notes:",
                "\(report.notes)",
                "",
                "App version/build: \(metadata.appVersion) (\(metadata.build))",
                "OS/device: \(metadata.osName) \(metadata.osVersion) on \(metadata.deviceModel)"
            ]

            if let userEmail = report.email?.trimmingCharacters(in: .whitespacesAndNewlines),
               !userEmail.isEmpty {
                bodyLines.append("User email: \(userEmail)")
            }

            bodyLines.append(attachmentLine)
            return bodyLines.joined(separator: "\n")
        }
    ) {
        self.recipients = recipients
        self.appName = appName
        self.subjectProvider = subjectProvider
        self.bodyProvider = bodyProvider
    }

    public static func standard(recipient: String, appName: String) -> AppReportEmailConfiguration {
        AppReportEmailConfiguration(
            recipients: [recipient],
            appName: appName,
            subjectProvider: { _ in
                "\(appName) Report"
            }
        )
    }
}

public enum AppReportDelivery: Sendable {
    case endpoint(AppReportClient)
    case email(AppReportEmailConfiguration)
    case endpointWithEmailFallback(
        AppReportClient,
        AppReportEmailConfiguration,
        fallbackPolicy: EmailFallbackPolicy
    )
    case custom(any AppReportSubmissionHandling, emailFallback: AppReportEmailConfiguration?)
}

public protocol MailAvailabilityChecking {
    func canSendMail() -> Bool
}

public struct SystemMailAvailabilityChecker: MailAvailabilityChecking {
    public init() {
        // Stateless wrapper used so mail availability stays injectable in tests.
    }

    public func canSendMail() -> Bool {
        #if canImport(MessageUI) && os(iOS)
        MFMailComposeViewController.canSendMail()
        #else
        false
        #endif
    }
}

public enum DiagnosticsDeliveryPlatform: String, Sendable {
    case iOS
    case macOS
    case other

    public static var current: DiagnosticsDeliveryPlatform {
        #if os(iOS)
        .iOS
        #elseif os(macOS)
        .macOS
        #else
        .other
        #endif
    }
}

public final class AppReportDiagnosticsSubmitter: @unchecked Sendable, FeedbackSubmitting, FeedbackFormSupportProviding, FeedbackFormPolicyProviding, FeedbackSubmissionRouteProviding {
    public struct Support {
        public let diagnosticsProvider: FeedbackDiagnosticsProvider?
        public let networkRecorder: NetworkRecorder?
        public let screenshotProvider: FeedbackScreenshotProviding?
        public let breadcrumbProvider: FeedbackBreadcrumbProviding?

        public init(
            diagnosticsProvider: FeedbackDiagnosticsProvider? = nil,
            networkRecorder: NetworkRecorder? = nil,
            screenshotProvider: FeedbackScreenshotProviding? = nil,
            breadcrumbProvider: FeedbackBreadcrumbProviding? = nil
        ) {
            self.diagnosticsProvider = diagnosticsProvider
            self.networkRecorder = networkRecorder
            self.screenshotProvider = screenshotProvider
            self.breadcrumbProvider = breadcrumbProvider
        }
    }

    public struct Configuration {
        public let bundleBuilder: DiagnosticsBundleBuilder
        public let bundlePackager: DiagnosticsBundlePackager
        public let mailAvailabilityChecker: MailAvailabilityChecking
        public let platform: DiagnosticsDeliveryPlatform
        public let attachBundleToEndpoint: Bool
        public let allowEndpointScreenshotAttachments: Bool
        public let dateProvider: @Sendable () -> Date

        public init(
            bundleBuilder: DiagnosticsBundleBuilder = DiagnosticsBundleBuilder(),
            bundlePackager: DiagnosticsBundlePackager = ZipDiagnosticsBundlePackager(),
            mailAvailabilityChecker: MailAvailabilityChecking = SystemMailAvailabilityChecker(),
            platform: DiagnosticsDeliveryPlatform = .current,
            attachBundleToEndpoint: Bool = false,
            allowEndpointScreenshotAttachments: Bool = true,
            dateProvider: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.bundleBuilder = bundleBuilder
            self.bundlePackager = bundlePackager
            self.mailAvailabilityChecker = mailAvailabilityChecker
            self.platform = platform
            self.attachBundleToEndpoint = attachBundleToEndpoint
            self.allowEndpointScreenshotAttachments = allowEndpointScreenshotAttachments
            self.dateProvider = dateProvider
        }
    }

    public let feedbackFormSupportOptions: FeedbackFormSupportOptions
    public let feedbackFormPolicy: FeedbackFormPolicy

    private let reportBuilder: FeedbackReportBuilder
    private let diagnosticsProvider: FeedbackDiagnosticsProvider?
    private let delivery: AppReportDelivery
    private let networkRecorder: NetworkRecorder?
    private let screenshotProvider: FeedbackScreenshotProviding?
    private let breadcrumbProvider: FeedbackBreadcrumbProviding?
    private let bundleBuilder: DiagnosticsBundleBuilder
    private let bundlePackager: DiagnosticsBundlePackager
    private let mailAvailabilityChecker: MailAvailabilityChecking
    private let platform: DiagnosticsDeliveryPlatform
    private let attachBundleToEndpoint: Bool
    private let allowEndpointScreenshotAttachments: Bool
    private let dateProvider: () -> Date
    private let diagnosticsRedactor: NetworkRedactor

    private struct PreparedSubmission {
        let request: FeedbackSubmissionRequest
        let providedDiagnostics: [String: String]
        let diagnostics: [String: String]
        let userAttachments: [FeedbackAttachment]
        let inlineScreenshotAttachments: [FeedbackAttachment]
        let networkEvents: [NetworkEvent]
        let screenshots: [DiagnosticsAttachment]
        let breadcrumbs: [FeedbackBreadcrumb]
        let submittedAt: Date

        var emailAttachments: [FeedbackAttachment] {
            userAttachments + inlineScreenshotAttachments
        }
    }

    public init(
        reportBuilder: FeedbackReportBuilder,
        delivery: AppReportDelivery,
        support: Support = .init(),
        configuration: Configuration = .init()
    ) {
        self.reportBuilder = reportBuilder
        diagnosticsProvider = support.diagnosticsProvider
        self.delivery = delivery
        networkRecorder = support.networkRecorder
        screenshotProvider = support.screenshotProvider
        breadcrumbProvider = support.breadcrumbProvider
        bundleBuilder = configuration.bundleBuilder
        bundlePackager = configuration.bundlePackager
        mailAvailabilityChecker = configuration.mailAvailabilityChecker
        platform = configuration.platform
        attachBundleToEndpoint = configuration.attachBundleToEndpoint
        allowEndpointScreenshotAttachments = configuration.allowEndpointScreenshotAttachments
        dateProvider = configuration.dateProvider
        diagnosticsRedactor = NetworkRedactor(policy: support.networkRecorder?.capturePolicy ?? .metadataOnly)
        feedbackFormPolicy = Self.feedbackFormPolicy(for: delivery)
        feedbackFormSupportOptions = FeedbackFormSupportOptions(
            allowsTechnicalDetails: support.networkRecorder != nil,
            allowsScreenshot: support.screenshotProvider != nil
        )
    }

    private static func feedbackFormPolicy(for delivery: AppReportDelivery) -> FeedbackFormPolicy {
        switch delivery {
        case .email:
            return FeedbackFormPolicy(
                .init(
                    emailOptions: .init(allowsEmail: false, requiresEmail: false)
                )
            )
        case .endpoint, .endpointWithEmailFallback, .custom:
            return .standard
        }
    }

    public var feedbackSubmissionRoute: FeedbackSubmissionRoute {
        switch delivery {
        case .endpoint, .endpointWithEmailFallback, .custom:
            return .endpoint
        case .email:
            switch platform {
            case .iOS:
                return mailAvailabilityChecker.canSendMail() ? .email : .share
            case .macOS:
                return .export
            case .other:
                return .unavailable
            }
        }
    }

    public func submit(_ request: FeedbackSubmissionRequest) async throws -> FeedbackSubmissionOutcome {
        let submittedAt = dateProvider()
        let screenshots = try loadScreenshots(
            includeScreenshot: request.includeScreenshot,
            screenshotAttachments: request.screenshotAttachments
        )
        let networkEvents = try await loadNetworkEvents(includeTechnicalDetails: request.includeTechnicalDetails)
        let breadcrumbs = redactBreadcrumbs(await loadBreadcrumbs())
        let providedDiagnostics = request.includeTechnicalDetails
            ? diagnosticsProvider?.makeDiagnostics() ?? [:]
            : [:]
        let diagnostics = buildDiagnostics(
            from: request.diagnostics,
            providedDiagnostics: providedDiagnostics,
            includeTechnicalDetails: request.includeTechnicalDetails,
            networkEvents: networkEvents
        )
        let inlineScreenshotAttachments = makeInlineScreenshotAttachments(from: screenshots)
        let prepared = PreparedSubmission(
            request: request,
            providedDiagnostics: providedDiagnostics,
            diagnostics: diagnostics,
            userAttachments: request.attachments,
            inlineScreenshotAttachments: inlineScreenshotAttachments,
            networkEvents: networkEvents,
            screenshots: screenshots,
            breadcrumbs: breadcrumbs,
            submittedAt: submittedAt
        )

        switch delivery {
        case let .endpoint(client):
            let report = try maybeAttachBundleToEndpoint(prepared: prepared)

            let response = try await client.submit(report)
            return .submitted(response)

        case let .email(emailConfiguration):
            return try await makePendingDelivery(prepared: prepared, emailConfiguration: emailConfiguration)

        case let .endpointWithEmailFallback(client, emailConfiguration, fallbackPolicy):
            do {
                let report = try maybeAttachBundleToEndpoint(prepared: prepared)

                let response = try await client.submit(report)
                return .submitted(response)
            } catch {
                guard fallbackPolicy.allowWhenEndpointFails else {
                    throw error
                }

                return try await makePendingDelivery(prepared: prepared, emailConfiguration: emailConfiguration)
            }

        case let .custom(handler, emailFallback):
            let unsupported = presentPayloads(prepared: prepared).subtracting(handler.capabilities)
            if !unsupported.isEmpty {
                return .needsConfirmation(
                    FeedbackSubmissionConfirmation(
                        unsupported: unsupported,
                        alternateDelivery: try await makeAlternateDelivery(
                            prepared: prepared,
                            emailFallback: emailFallback
                        )
                    )
                )
            }

            let preparedSubmission = try makePreparedAppReportSubmission(
                prepared: prepared,
                includeDiagnosticsBundle: prepared.request.includeTechnicalDetails
                    && handler.capabilities.contains(.files)
                    && hasOptionalLogs(prepared: prepared)
            )
            try await handler.submit(preparedSubmission)
            return .submitted(
                AppReportSubmissionResponse(accepted: true, statusCode: 200)
            )
        }
    }

    private func loadScreenshots(
        includeScreenshot: Bool,
        screenshotAttachments: [FeedbackAttachment]
    ) throws -> [DiagnosticsAttachment] {
        guard includeScreenshot else {
            return []
        }

        if !screenshotAttachments.isEmpty {
            return screenshotAttachments.compactMap { attachment in
                guard let data = attachment.data else {
                    return nil
                }

                return DiagnosticsAttachment(
                    data: data,
                    filename: attachment.filename,
                    contentType: attachment.contentType,
                    description: nil
                )
            }
        }

        return try screenshotProvider?.makeScreenshots().map(DiagnosticsAttachment.init) ?? []
    }

    private func loadBreadcrumbs() async -> [FeedbackBreadcrumb] {
        await breadcrumbProvider?.currentBreadcrumbs() ?? []
    }

    private func redactBreadcrumbs(_ breadcrumbs: [FeedbackBreadcrumb]) -> [FeedbackBreadcrumb] {
        breadcrumbs.map {
            FeedbackBreadcrumb(
                timestamp: $0.timestamp,
                title: $0.title,
                metadata: diagnosticsRedactor.redactMetadata($0.metadata)
            )
        }
    }

    private func loadNetworkEvents(includeTechnicalDetails: Bool) async throws -> [NetworkEvent] {
        guard includeTechnicalDetails else {
            return []
        }

        return await networkRecorder?.snapshot() ?? []
    }

    private func buildDiagnostics(
        from initialDiagnostics: [String: String],
        providedDiagnostics: [String: String],
        includeTechnicalDetails: Bool,
        networkEvents: [NetworkEvent]
    ) -> [String: String] {
        var diagnostics = initialDiagnostics

        if includeTechnicalDetails {
            diagnostics.merge(providedDiagnostics) { _, newValue in
                newValue
            }
            diagnostics["technicalDetailsIncluded"] = "true"
            diagnostics["networkEventCount"] = String(networkEvents.count)
        }

        return diagnosticsRedactor.redactMetadata(diagnostics)
    }

    private func presentPayloads(
        prepared: PreparedSubmission
    ) -> AppReportSubmissionCapabilities {
        var payloads: AppReportSubmissionCapabilities = []

        if !prepared.userAttachments.isEmpty
            || (prepared.request.includeTechnicalDetails && hasOptionalLogs(prepared: prepared)) {
            payloads.insert(.files)
        }

        if !prepared.screenshots.isEmpty {
            payloads.insert(.images)
        }

        return payloads
    }

    private func makeInlineScreenshotAttachments(from screenshots: [DiagnosticsAttachment]) -> [FeedbackAttachment] {
        guard allowEndpointScreenshotAttachments else {
            return []
        }

        return screenshots.map {
            FeedbackAttachment(
                filename: $0.sanitizedFilename(fallback: "screenshot.png"),
                contentType: $0.contentType,
                data: $0.data
            )
        }
    }

    private func maybeAttachBundleToEndpoint(prepared: PreparedSubmission) throws -> FeedbackReport {
        let includesBundleAttachments = attachBundleToEndpoint && prepared.request.includeTechnicalDetails
        let reportAttachments = includesBundleAttachments
            ? prepared.userAttachments
            : prepared.emailAttachments
        let report = reportBuilder.makeReport(
            details: prepared.request.details,
            diagnostics: prepared.diagnostics,
            attachments: reportAttachments,
            breadcrumbs: prepared.breadcrumbs
        )

        guard includesBundleAttachments else {
            return report
        }

        let bundle = try bundleBuilder.build(
            report: report,
            submittedAt: prepared.submittedAt,
            networkEvents: prepared.networkEvents,
            screenshots: prepared.screenshots
        )
        defer {
            try? bundleBuilder.cleanup(bundle)
        }
        let bundleAttachments = try bundleBuilder.makeEndpointAttachments(from: bundle)

        return reportBuilder.makeReport(
            details: prepared.request.details,
            diagnostics: prepared.diagnostics,
            attachments: prepared.userAttachments + bundleAttachments,
            breadcrumbs: prepared.breadcrumbs
        )
    }

    private func makePendingDelivery(
        prepared: PreparedSubmission,
        emailConfiguration: AppReportEmailConfiguration
    ) async throws -> FeedbackSubmissionOutcome {
        let report = reportBuilder.makeReport(
            details: prepared.request.details,
            diagnostics: prepared.diagnostics,
            attachments: prepared.emailAttachments,
            breadcrumbs: prepared.breadcrumbs
        )
        let bundle = try bundleBuilder.build(
            report: report,
            submittedAt: prepared.submittedAt,
            networkEvents: prepared.networkEvents,
            screenshots: prepared.screenshots
        )
        let subject = emailConfiguration.subjectProvider(report)
        let body = emailConfiguration.bodyProvider(report, !bundle.fileAttachments.isEmpty)

        if platform == .iOS, mailAvailabilityChecker.canSendMail() {
            return .needsUserAction(
                .email(
                    FeedbackPendingEmail(
                        recipients: emailConfiguration.recipients,
                        subject: subject,
                        body: body,
                        attachments: bundle.fileAttachments,
                        temporaryDirectoryURL: bundle.rootURL
                    )
                )
            )
        }

        let packageURL: URL
        do {
            packageURL = try bundlePackager.package(
                at: bundle.rootURL,
                filename: bundlePackageFilename(for: prepared.submittedAt)
            )
        } catch {
            try? bundleBuilder.cleanup(bundle)
            throw error
        }
        return .needsUserAction(
            .share(
                FeedbackPendingShare(
                    subject: subject,
                    message: body,
                    itemURLs: [packageURL],
                    temporaryDirectoryURL: bundle.rootURL
                )
            )
        )
    }

    private func makeAlternateDelivery(
        prepared: PreparedSubmission,
        emailFallback: AppReportEmailConfiguration?
    ) async throws -> FeedbackPendingDelivery? {
        guard let emailFallback else {
            return nil
        }

        return try await makePendingDelivery(
            prepared: prepared,
            emailConfiguration: emailFallback
        ).pendingDelivery
    }

    private func makePreparedAppReportSubmission(
        prepared: PreparedSubmission,
        includeDiagnosticsBundle: Bool
    ) throws -> PreparedAppReportSubmission {
        let report = reportBuilder.makeReport(
            details: prepared.request.details,
            diagnostics: prepared.diagnostics,
            attachments: prepared.emailAttachments,
            breadcrumbs: prepared.breadcrumbs
        )
        let bundle = includeDiagnosticsBundle
            ? try makeDiagnosticsBundle(prepared: prepared, report: report)
            : nil
        return PreparedAppReportSubmission(
            report: report.appReportPayload(),
            metadata: report.metadata.appReportMetadata(capturedAt: prepared.submittedAt),
            attachments: makePreparedAppReportAttachments(
                userAttachments: prepared.userAttachments,
                screenshotAttachments: makePreparedScreenshotAttachments(from: prepared.screenshots)
            ),
            diagnosticsBundle: bundle
        )
    }

    private func hasOptionalLogs(prepared: PreparedSubmission) -> Bool {
        !prepared.request.diagnostics.isEmpty
            || !prepared.providedDiagnostics.isEmpty
            || !prepared.networkEvents.isEmpty
            || !prepared.breadcrumbs.isEmpty
    }

    private func makeDiagnosticsBundle(
        prepared: PreparedSubmission,
        report: FeedbackReport
    ) throws -> AppReportBundle? {
        let bundle = try bundleBuilder.build(
            report: report,
            submittedAt: prepared.submittedAt,
            networkEvents: prepared.networkEvents,
            screenshots: prepared.screenshots
        )
        defer {
            try? bundleBuilder.cleanup(bundle)
        }

        let packageURL = try bundlePackager.package(
            at: bundle.rootURL,
            filename: bundlePackageFilename(for: prepared.submittedAt)
        )
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        let data = try Data(contentsOf: packageURL)
        return AppReportBundle(
            fileName: packageURL.lastPathComponent,
            mimeType: "application/zip",
            data: data
        )
    }

    private func makePreparedAppReportAttachments(
        userAttachments: [FeedbackAttachment],
        screenshotAttachments: [FeedbackAttachment]
    ) -> [AppReportAttachment] {
        userAttachments.preparedAppReportAttachments(kind: .attachment)
            + screenshotAttachments.preparedAppReportAttachments(kind: .screenshot)
    }

    private func makePreparedScreenshotAttachments(
        from screenshots: [DiagnosticsAttachment]
    ) -> [FeedbackAttachment] {
        screenshots.map {
            FeedbackAttachment(
                filename: $0.sanitizedFilename(fallback: "screenshot.png"),
                contentType: $0.contentType,
                data: $0.data
            )
        }
    }

    private func bundlePackageFilename(for date: Date) -> String {
        "AppReportDiagnostics-\(timestampString(from: date)).apprdiag.zip"
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return formatter.string(from: date)
    }
}

private extension FeedbackSubmissionOutcome {
    var pendingDelivery: FeedbackPendingDelivery? {
        guard case let .needsUserAction(delivery) = self else {
            return nil
        }

        return delivery
    }
}

public enum DiagnosticsDeliveryCleanup {
    public static func cleanup(
        _ delivery: FeedbackPendingDelivery,
        fileManager: FileManager = .default
    ) throws {
        try FeedbackPendingDeliveryCleanup.cleanup(delivery, fileManager: fileManager)
    }
}
