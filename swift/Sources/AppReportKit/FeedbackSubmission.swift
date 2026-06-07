import Foundation

public struct FeedbackSubmissionRequest: Equatable, Sendable {
    public struct Options: Equatable, Sendable {
        public let includeTechnicalDetails: Bool
        public let includeScreenshot: Bool

        public init(
            includeTechnicalDetails: Bool = false,
            includeScreenshot: Bool = false
        ) {
            self.includeTechnicalDetails = includeTechnicalDetails
            self.includeScreenshot = includeScreenshot
        }
    }

    public struct Payload: Equatable, Sendable {
        public let diagnostics: [String: String]
        public let attachments: [FeedbackAttachment]

        public init(
            diagnostics: [String: String] = [:],
            attachments: [FeedbackAttachment] = []
        ) {
            self.diagnostics = diagnostics
            self.attachments = attachments
        }
    }

    public let kind: FeedbackReportKind
    public let notes: String
    public let severity: FeedbackSeverity
    public let email: String?
    public let screen: String?
    public let includeTechnicalDetails: Bool
    public let includeScreenshot: Bool
    public let diagnostics: [String: String]
    public let attachments: [FeedbackAttachment]

    public init(
        kind: FeedbackReportKind,
        notes: String,
        severity: FeedbackSeverity = .normal,
        email: String? = nil,
        screen: String? = nil,
        options: Options = .init(),
        payload: Payload = .init()
    ) {
        self.kind = kind
        self.notes = notes
        self.severity = severity
        self.email = email
        self.screen = screen
        includeTechnicalDetails = options.includeTechnicalDetails
        includeScreenshot = options.includeScreenshot
        diagnostics = payload.diagnostics
        attachments = payload.attachments
    }
}

public struct FeedbackPreparedAttachment: Equatable, Sendable {
    public let fileURL: URL
    public let contentType: String

    public init(fileURL: URL, contentType: String) {
        self.fileURL = fileURL
        self.contentType = contentType
    }
}

public struct FeedbackPendingEmail: Equatable, Sendable {
    public let recipients: [String]
    public let subject: String
    public let body: String
    public let attachments: [FeedbackPreparedAttachment]
    public let temporaryDirectoryURL: URL?

    public init(
        recipients: [String],
        subject: String,
        body: String,
        attachments: [FeedbackPreparedAttachment],
        temporaryDirectoryURL: URL? = nil
    ) {
        self.recipients = recipients
        self.subject = subject
        self.body = body
        self.attachments = attachments
        self.temporaryDirectoryURL = temporaryDirectoryURL
    }
}

public struct FeedbackPendingShare: Equatable, Sendable {
    public let subject: String
    public let message: String
    public let itemURLs: [URL]
    public let temporaryDirectoryURL: URL?

    public init(
        subject: String,
        message: String,
        itemURLs: [URL],
        temporaryDirectoryURL: URL? = nil
    ) {
        self.subject = subject
        self.message = message
        self.itemURLs = itemURLs
        self.temporaryDirectoryURL = temporaryDirectoryURL
    }
}

public enum FeedbackPendingDelivery: Equatable, Sendable {
    case email(FeedbackPendingEmail)
    case share(FeedbackPendingShare)
}

public enum FeedbackSubmissionOutcome: Equatable, Sendable {
    case submitted(AppReportSubmissionResponse)
    case needsUserAction(FeedbackPendingDelivery)
}

public struct FeedbackFormSupportOptions: Equatable, Sendable {
    public let allowsTechnicalDetails: Bool
    public let allowsScreenshot: Bool
    public let technicalDetailsEnabledByDefault: Bool
    public let screenshotEnabledByDefault: Bool

    public init(
        allowsTechnicalDetails: Bool = false,
        allowsScreenshot: Bool = false,
        technicalDetailsEnabledByDefault: Bool = false,
        screenshotEnabledByDefault: Bool = false
    ) {
        self.allowsTechnicalDetails = allowsTechnicalDetails
        self.allowsScreenshot = allowsScreenshot
        self.technicalDetailsEnabledByDefault = technicalDetailsEnabledByDefault
        self.screenshotEnabledByDefault = screenshotEnabledByDefault
    }

    public static let disabled = FeedbackFormSupportOptions()
}

public struct FeedbackScreenshot: Equatable, Sendable {
    public let data: Data
    public let filename: String
    public let contentType: String
    public let description: String?

    public init(
        data: Data,
        filename: String,
        contentType: String,
        description: String? = nil
    ) {
        self.data = data
        self.filename = filename
        self.contentType = contentType
        self.description = description
    }
}

public protocol FeedbackScreenshotProviding {
    func makeScreenshots() throws -> [FeedbackScreenshot]
}

public protocol FeedbackSubmitting {
    func submit(_ request: FeedbackSubmissionRequest) async throws -> FeedbackSubmissionOutcome
}

public protocol FeedbackFormSupportProviding {
    var feedbackFormSupportOptions: FeedbackFormSupportOptions { get }
}
