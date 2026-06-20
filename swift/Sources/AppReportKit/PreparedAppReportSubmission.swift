import Foundation

public struct AppReportPayload: Equatable, Sendable {
    public let type: String
    public let context: String?
    public let title: String?
    public let notes: String
    public let reporterEmail: String?
    public let severity: String?

    public init(
        type: String,
        context: String? = nil,
        title: String? = nil,
        notes: String,
        reporterEmail: String? = nil,
        severity: String? = nil
    ) {
        self.type = type
        self.context = context
        self.title = title
        self.notes = notes
        self.reporterEmail = reporterEmail
        self.severity = severity
    }
}

public struct AppReportMetadata: Equatable, Sendable {
    public let appVersion: String?
    public let buildNumber: String?
    public let osVersion: String?
    public let deviceModel: String?
    public let localeIdentifier: String?
    public let timezoneIdentifier: String?
    public let capturedAt: Date

    public init(
        appVersion: String? = nil,
        buildNumber: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        localeIdentifier: String? = nil,
        timezoneIdentifier: String? = nil,
        capturedAt: Date
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.localeIdentifier = localeIdentifier
        self.timezoneIdentifier = timezoneIdentifier
        self.capturedAt = capturedAt
    }
}

public struct AppReportAttachment: Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case attachment
        case screenshot
        case diagnosticsBundle
    }

    public let kind: Kind
    public let fileName: String
    public let mimeType: String
    public let data: Data

    public init(
        kind: Kind,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

public struct AppReportBundle: Equatable, Sendable {
    public let fileName: String
    public let mimeType: String
    public let data: Data

    public init(
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

public struct PreparedAppReportSubmission: Equatable, Sendable {
    public let report: AppReportPayload
    public let metadata: AppReportMetadata
    public let attachments: [AppReportAttachment]
    public let diagnosticsBundle: AppReportBundle?

    public init(
        report: AppReportPayload,
        metadata: AppReportMetadata,
        attachments: [AppReportAttachment],
        diagnosticsBundle: AppReportBundle? = nil
    ) {
        self.report = report
        self.metadata = metadata
        self.attachments = attachments
        self.diagnosticsBundle = diagnosticsBundle
    }
}

public protocol AppReportSubmissionHandling: Sendable {
    func submit(_ submission: PreparedAppReportSubmission) async throws
}

public extension FeedbackSubmissionRequest {
    func preparedAppReportSubmission(
        metadataProvider: FeedbackMetadataProviding,
        capturedAt: Date = Date(),
        diagnosticsBundle: AppReportBundle? = nil
    ) -> PreparedAppReportSubmission {
        let metadata = metadataProvider.makeMetadata(screen: screen)
        let preparedMetadata = metadata.appReportMetadata(capturedAt: capturedAt)
        let attachments = Self.makePreparedAttachments(
            from: self.attachments,
            kind: .attachment
        ) + Self.makePreparedAttachments(
            from: screenshotAttachments,
            kind: .screenshot
        )

        return PreparedAppReportSubmission(
            report: AppReportPayload(
                type: kind.rawValue,
                context: screen?.nilIfBlank,
                title: kind.rawValue.capitalized,
                notes: notes,
                reporterEmail: email?.nilIfBlank,
                severity: severity.rawValue
            ),
            metadata: preparedMetadata,
            attachments: attachments,
            diagnosticsBundle: diagnosticsBundle
        )
    }

    private static func makePreparedAttachments(
        from attachments: [FeedbackAttachment],
        kind: AppReportAttachment.Kind
    ) -> [AppReportAttachment] {
        attachments.compactMap { attachment in
            guard let data = attachment.resolvedData else {
                return nil
            }

            return AppReportAttachment(
                kind: kind,
                fileName: attachment.filename,
                mimeType: attachment.contentType,
                data: data
            )
        }
    }
}

public extension FeedbackMetadata {
    func appReportMetadata(capturedAt: Date) -> AppReportMetadata {
        AppReportMetadata(
            appVersion: appVersion,
            buildNumber: build,
            osVersion: osVersion,
            deviceModel: deviceModel,
            localeIdentifier: locale,
            timezoneIdentifier: TimeZone.current.identifier,
            capturedAt: capturedAt
        )
    }
}

public extension FeedbackReport {
    func appReportPayload() -> AppReportPayload {
        AppReportPayload(
            type: kind.rawValue,
            context: metadata.screen,
            title: kind.rawValue.capitalized,
            notes: notes,
            reporterEmail: email,
            severity: severity.rawValue
        )
    }
}

public extension FeedbackAttachment {
    var resolvedData: Data? {
        if let data {
            return data
        }

        guard let url else {
            return nil
        }

        if url.contains("://"), let parsedURL = URL(string: url), parsedURL.isFileURL {
            return try? Data(contentsOf: parsedURL)
        }

        let fileURL = URL(fileURLWithPath: url)
        guard fileURL.isFileURL else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
