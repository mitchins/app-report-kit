import AppReportKit
import Foundation

#if canImport(MessageUI)
import MessageUI
#endif

public struct EmailFallbackPolicy: Equatable, Sendable {
    public let allowWhenNoEndpointConfigured: Bool
    public let allowWhenEndpointFails: Bool

    public init(
        allowWhenNoEndpointConfigured: Bool = true,
        allowWhenEndpointFails: Bool = false
    ) {
        self.allowWhenNoEndpointConfigured = allowWhenNoEndpointConfigured
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
            return """
            Notes:
            \(report.notes)

            App version/build: \(metadata.appVersion) (\(metadata.build))
            OS/device: \(metadata.osName) \(metadata.osVersion) on \(metadata.deviceModel)
            User email: \(report.email ?? "Not provided")
            \(attachmentLine)
            """
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
        feedbackFormPolicy = .standard
        feedbackFormSupportOptions = FeedbackFormSupportOptions(
            allowsTechnicalDetails: support.networkRecorder != nil,
            allowsScreenshot: support.screenshotProvider != nil
        )
    }

    public var feedbackSubmissionRoute: FeedbackSubmissionRoute {
        switch delivery {
        case .endpoint, .endpointWithEmailFallback:
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
        let diagnostics = buildDiagnostics(
            from: request.diagnostics,
            includeTechnicalDetails: request.includeTechnicalDetails,
            networkEvents: networkEvents
        )
        let inlineScreenshotAttachments = makeInlineScreenshotAttachments(from: screenshots)
        let baseAttachments = request.attachments + inlineScreenshotAttachments

        switch delivery {
        case let .endpoint(client):
            let report = try maybeAttachBundleToEndpoint(
                request: request,
                diagnostics: diagnostics,
                attachments: request.attachments,
                inlineScreenshotAttachments: inlineScreenshotAttachments,
                networkEvents: networkEvents,
                screenshots: screenshots,
                breadcrumbs: breadcrumbs,
                submittedAt: submittedAt
            )

            let response = try await client.submit(report)
            return .submitted(response)

        case let .email(emailConfiguration):
            return try await makePendingDelivery(
                request: request,
                diagnostics: diagnostics,
                attachments: baseAttachments,
                networkEvents: networkEvents,
                screenshots: screenshots,
                breadcrumbs: breadcrumbs,
                submittedAt: submittedAt,
                emailConfiguration: emailConfiguration
            )

        case let .endpointWithEmailFallback(client, emailConfiguration, fallbackPolicy):
            do {
                let report = try maybeAttachBundleToEndpoint(
                    request: request,
                    diagnostics: diagnostics,
                    attachments: request.attachments,
                    inlineScreenshotAttachments: inlineScreenshotAttachments,
                    networkEvents: networkEvents,
                    screenshots: screenshots,
                    breadcrumbs: breadcrumbs,
                    submittedAt: submittedAt
                )

                let response = try await client.submit(report)
                return .submitted(response)
            } catch {
                guard fallbackPolicy.allowWhenEndpointFails else {
                    throw error
                }

                return try await makePendingDelivery(
                    request: request,
                    diagnostics: diagnostics,
                    attachments: baseAttachments,
                    networkEvents: networkEvents,
                    screenshots: screenshots,
                    breadcrumbs: breadcrumbs,
                    submittedAt: submittedAt,
                    emailConfiguration: emailConfiguration
                )
            }
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
        includeTechnicalDetails: Bool,
        networkEvents: [NetworkEvent]
    ) -> [String: String] {
        var diagnostics = initialDiagnostics

        if includeTechnicalDetails {
            diagnostics.merge(diagnosticsProvider?.makeDiagnostics() ?? [:]) { _, newValue in
                newValue
            }
            diagnostics["technicalDetailsIncluded"] = "true"
            diagnostics["networkEventCount"] = String(networkEvents.count)
        }

        return diagnosticsRedactor.redactMetadata(diagnostics)
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

    private func maybeAttachBundleToEndpoint(
        request: FeedbackSubmissionRequest,
        diagnostics: [String: String],
        attachments: [FeedbackAttachment],
        inlineScreenshotAttachments: [FeedbackAttachment],
        networkEvents: [NetworkEvent],
        screenshots: [DiagnosticsAttachment],
        breadcrumbs: [FeedbackBreadcrumb],
        submittedAt: Date
    ) throws -> FeedbackReport {
        let includesBundleAttachments = attachBundleToEndpoint && request.includeTechnicalDetails
        let reportAttachments = includesBundleAttachments
            ? attachments
            : attachments + inlineScreenshotAttachments
        let report = reportBuilder.makeReport(
            kind: request.kind,
            notes: request.notes,
            severity: request.severity,
            email: request.email,
            screen: request.screen,
            diagnostics: diagnostics,
            attachments: reportAttachments,
            breadcrumbs: breadcrumbs
        )

        guard includesBundleAttachments else {
            return report
        }

        let bundle = try bundleBuilder.build(
            report: report,
            submittedAt: submittedAt,
            networkEvents: networkEvents,
            screenshots: screenshots
        )
        defer {
            try? bundleBuilder.cleanup(bundle)
        }
        let bundleAttachments = try bundleBuilder.makeEndpointAttachments(from: bundle)

        return reportBuilder.makeReport(
            kind: request.kind,
            notes: request.notes,
            severity: request.severity,
            email: request.email,
            screen: request.screen,
            diagnostics: diagnostics,
            attachments: attachments + bundleAttachments,
            breadcrumbs: breadcrumbs
        )
    }

    private func makePendingDelivery(
        request: FeedbackSubmissionRequest,
        diagnostics: [String: String],
        attachments: [FeedbackAttachment],
        networkEvents: [NetworkEvent],
        screenshots: [DiagnosticsAttachment],
        breadcrumbs: [FeedbackBreadcrumb],
        submittedAt: Date,
        emailConfiguration: AppReportEmailConfiguration
    ) async throws -> FeedbackSubmissionOutcome {
        let report = reportBuilder.makeReport(
            kind: request.kind,
            notes: request.notes,
            severity: request.severity,
            email: request.email,
            screen: request.screen,
            diagnostics: diagnostics,
            attachments: attachments,
            breadcrumbs: breadcrumbs
        )
        let bundle = try bundleBuilder.build(
            report: report,
            submittedAt: submittedAt,
            networkEvents: networkEvents,
            screenshots: screenshots
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

        let packageURL = try bundlePackager.package(
            at: bundle.rootURL,
            filename: bundlePackageFilename(for: submittedAt)
        )
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

public enum DiagnosticsDeliveryCleanup {
    public static func cleanup(
        _ delivery: FeedbackPendingDelivery,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL: URL?
        switch delivery {
        case let .email(email):
            directoryURL = email.temporaryDirectoryURL
        case let .share(share):
            directoryURL = share.temporaryDirectoryURL
        }

        guard let directoryURL, fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        try fileManager.removeItem(at: directoryURL)
    }
}
