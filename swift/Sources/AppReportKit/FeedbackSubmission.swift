import Foundation

public enum FeedbackSubmissionRoute: String, Codable, Sendable {
    case endpoint
    case email
    case share
    case export
    case unavailable
}

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
    public let screenshotAttachments: [FeedbackAttachment]

    public init(
        kind: FeedbackReportKind,
        notes: String,
        severity: FeedbackSeverity = .normal,
        email: String? = nil,
        screen: String? = nil,
        options: Options = .init(),
        payload: Payload = .init(),
        screenshotAttachments: [FeedbackAttachment] = []
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
        self.screenshotAttachments = screenshotAttachments
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

public struct FeedbackBreadcrumb: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let title: String
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        title: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.title = title
        self.metadata = metadata
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

public struct FeedbackFormPolicy: Equatable, Sendable {
    public let allowedKinds: [FeedbackReportKind]
    public let defaultKind: FeedbackReportKind
    public let showsKindPicker: Bool
    public let showsSeverityPicker: Bool
    public let defaultSeverity: FeedbackSeverity
    public let allowsEmail: Bool
    public let requiresEmail: Bool
    public let allowsTechnicalDetails: Bool
    public let technicalDetailsDefaultOn: Bool
    public let allowsScreenshot: Bool
    public let screenshotDefaultOn: Bool
    public let requiresNotes: Bool

    public init(
        allowedKinds: [FeedbackReportKind] = FeedbackReportKind.allCases,
        defaultKind: FeedbackReportKind = .bug,
        showsKindPicker: Bool = true,
        showsSeverityPicker: Bool = true,
        defaultSeverity: FeedbackSeverity = .normal,
        allowsEmail: Bool = true,
        requiresEmail: Bool = false,
        allowsTechnicalDetails: Bool = false,
        technicalDetailsDefaultOn: Bool = false,
        allowsScreenshot: Bool = false,
        screenshotDefaultOn: Bool = false,
        requiresNotes: Bool = true
    ) {
        var distinctKinds: [FeedbackReportKind] = []
        for kind in allowedKinds.isEmpty ? FeedbackReportKind.allCases : allowedKinds {
            if !distinctKinds.contains(kind) {
                distinctKinds.append(kind)
            }
        }

        let safeRequiresEmail = requiresEmail && allowsEmail
        let normalizedDefaultKind = distinctKinds.contains(defaultKind) ? defaultKind : distinctKinds[0]

        self.allowedKinds = distinctKinds
        self.defaultKind = normalizedDefaultKind
        self.showsKindPicker = showsKindPicker
        self.showsSeverityPicker = showsSeverityPicker
        self.defaultSeverity = defaultSeverity
        self.allowsEmail = allowsEmail
        self.requiresEmail = safeRequiresEmail
        self.allowsTechnicalDetails = allowsTechnicalDetails
        self.technicalDetailsDefaultOn = technicalDetailsDefaultOn
        self.allowsScreenshot = allowsScreenshot
        self.screenshotDefaultOn = screenshotDefaultOn
        self.requiresNotes = requiresNotes
    }

    public static let standard = FeedbackFormPolicy()

    public static let simpleIssue = FeedbackFormPolicy(
        allowedKinds: [.bug],
        defaultKind: .bug,
        showsKindPicker: false,
        showsSeverityPicker: false,
        allowsEmail: true,
        requiresEmail: false,
        technicalDetailsDefaultOn: false,
        screenshotDefaultOn: false
    )

    public static let bugOnly = FeedbackFormPolicy(
        allowedKinds: [.bug],
        defaultKind: .bug,
        showsKindPicker: false,
        showsSeverityPicker: false,
        allowsTechnicalDetails: true,
        technicalDetailsDefaultOn: true
    )

    public static let feedbackOnly = FeedbackFormPolicy(
        allowedKinds: [.feedback],
        defaultKind: .feedback,
        showsKindPicker: false,
        showsSeverityPicker: false,
        allowsEmail: false,
        allowsTechnicalDetails: false,
        allowsScreenshot: false
    )

    public static let clientDebug = FeedbackFormPolicy(
        allowedKinds: [.bug],
        defaultKind: .bug,
        showsKindPicker: false,
        showsSeverityPicker: true,
        allowsTechnicalDetails: true,
        technicalDetailsDefaultOn: true,
        allowsScreenshot: true,
        screenshotDefaultOn: true
    )

    public var showsKindPickerWhenNeeded: Bool {
        allowedKinds.count > 1 && showsKindPicker
    }

    public func with(
        showsKindPicker: Bool? = nil,
        showsSeverityPicker: Bool? = nil
    ) -> FeedbackFormPolicy {
        FeedbackFormPolicy(
            allowedKinds: allowedKinds,
            defaultKind: defaultKind,
            showsKindPicker: showsKindPicker ?? self.showsKindPicker,
            showsSeverityPicker: showsSeverityPicker ?? self.showsSeverityPicker,
            defaultSeverity: defaultSeverity,
            allowsEmail: allowsEmail,
            requiresEmail: requiresEmail,
            allowsTechnicalDetails: allowsTechnicalDetails,
            technicalDetailsDefaultOn: technicalDetailsDefaultOn,
            allowsScreenshot: allowsScreenshot,
            screenshotDefaultOn: screenshotDefaultOn,
            requiresNotes: requiresNotes
        )
    }
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

public protocol FeedbackBreadcrumbProviding {
    func currentBreadcrumbs() async -> [FeedbackBreadcrumb]
}

public protocol FeedbackSubmitting {
    func submit(_ request: FeedbackSubmissionRequest) async throws -> FeedbackSubmissionOutcome
}

public protocol FeedbackSubmissionRouteProviding {
    var feedbackSubmissionRoute: FeedbackSubmissionRoute { get }
}

public protocol FeedbackFormSupportProviding {
    var feedbackFormSupportOptions: FeedbackFormSupportOptions { get }
}

public protocol FeedbackFormPolicyProviding {
    var feedbackFormPolicy: FeedbackFormPolicy { get }
}
