import Foundation

public enum FeedbackSubmissionRoute: String, Codable, Sendable {
    case endpoint
    case email
    case share
    case export
    case unavailable
}

public struct FeedbackSubmissionRequest: Equatable, Sendable {
    public struct Details: Equatable, Sendable {
        public let kind: FeedbackReportKind
        public let notes: String
        public let severity: FeedbackSeverity
        public let email: String?
        public let screen: String?

        public init(
            kind: FeedbackReportKind,
            notes: String,
            severity: FeedbackSeverity = .normal,
            email: String? = nil,
            screen: String? = nil
        ) {
            self.kind = kind
            self.notes = notes
            self.severity = severity
            self.email = email
            self.screen = screen
        }
    }

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

    public var details: Details {
        Details(
            kind: kind,
            notes: notes,
            severity: severity,
            email: email,
            screen: screen
        )
    }

    public init(
        details: Details,
        options: Options = .init(),
        payload: Payload = .init(),
        screenshotAttachments: [FeedbackAttachment] = []
    ) {
        kind = details.kind
        notes = details.notes
        severity = details.severity
        email = details.email
        screen = details.screen
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

public struct FeedbackSubmissionConfirmation: Equatable, Sendable {
    public let unsupported: AppReportSubmissionCapabilities
    public let alternateDelivery: FeedbackPendingDelivery?

    public init(
        unsupported: AppReportSubmissionCapabilities,
        alternateDelivery: FeedbackPendingDelivery? = nil
    ) {
        self.unsupported = unsupported
        self.alternateDelivery = alternateDelivery
    }
}

public enum FeedbackSubmissionOutcome: Equatable, Sendable {
    case submitted(AppReportSubmissionResponse)
    case needsUserAction(FeedbackPendingDelivery)
    case needsConfirmation(FeedbackSubmissionConfirmation)
}

public enum FeedbackPendingDeliveryCleanup {
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
    public struct KindOptions: Equatable, Sendable {
        public let allowedKinds: [FeedbackReportKind]
        public let defaultKind: FeedbackReportKind
        public let showsKindPicker: Bool

        public init(
            allowedKinds: [FeedbackReportKind] = FeedbackReportKind.allCases,
            defaultKind: FeedbackReportKind = .bug,
            showsKindPicker: Bool = true
        ) {
            self.allowedKinds = allowedKinds
            self.defaultKind = defaultKind
            self.showsKindPicker = showsKindPicker
        }
    }

    public struct SeverityOptions: Equatable, Sendable {
        public let showsSeverityPicker: Bool
        public let defaultSeverity: FeedbackSeverity

        public init(
            showsSeverityPicker: Bool = true,
            defaultSeverity: FeedbackSeverity = .normal
        ) {
            self.showsSeverityPicker = showsSeverityPicker
            self.defaultSeverity = defaultSeverity
        }
    }

    public struct EmailOptions: Equatable, Sendable {
        public let allowsEmail: Bool
        public let requiresEmail: Bool

        public init(
            allowsEmail: Bool = true,
            requiresEmail: Bool = false
        ) {
            self.allowsEmail = allowsEmail
            self.requiresEmail = requiresEmail
        }
    }

    public struct TechnicalDetailsOptions: Equatable, Sendable {
        public let allowsTechnicalDetails: Bool
        public let technicalDetailsDefaultOn: Bool

        public init(
            allowsTechnicalDetails: Bool = false,
            technicalDetailsDefaultOn: Bool = false
        ) {
            self.allowsTechnicalDetails = allowsTechnicalDetails
            self.technicalDetailsDefaultOn = technicalDetailsDefaultOn
        }
    }

    public struct ScreenshotOptions: Equatable, Sendable {
        public let allowsScreenshot: Bool
        public let screenshotDefaultOn: Bool

        public init(
            allowsScreenshot: Bool = false,
            screenshotDefaultOn: Bool = false
        ) {
            self.allowsScreenshot = allowsScreenshot
            self.screenshotDefaultOn = screenshotDefaultOn
        }
    }

    public struct NotesOptions: Equatable, Sendable {
        public let requiresNotes: Bool

        public init(requiresNotes: Bool = true) {
            self.requiresNotes = requiresNotes
        }
    }

    public struct Configuration: Equatable, Sendable {
        public let kindOptions: KindOptions
        public let severityOptions: SeverityOptions
        public let emailOptions: EmailOptions
        public let technicalDetailsOptions: TechnicalDetailsOptions
        public let screenshotOptions: ScreenshotOptions
        public let notesOptions: NotesOptions

        public init(
            kindOptions: KindOptions = .init(),
            severityOptions: SeverityOptions = .init(),
            emailOptions: EmailOptions = .init(),
            technicalDetailsOptions: TechnicalDetailsOptions = .init(),
            screenshotOptions: ScreenshotOptions = .init(),
            notesOptions: NotesOptions = .init()
        ) {
            self.kindOptions = kindOptions
            self.severityOptions = severityOptions
            self.emailOptions = emailOptions
            self.technicalDetailsOptions = technicalDetailsOptions
            self.screenshotOptions = screenshotOptions
            self.notesOptions = notesOptions
        }
    }

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

    public init(_ configuration: Configuration = .init()) {
        var distinctKinds: [FeedbackReportKind] = []
        for kind in configuration.kindOptions.allowedKinds.isEmpty ? FeedbackReportKind.allCases : configuration.kindOptions.allowedKinds {
            if !distinctKinds.contains(kind) {
                distinctKinds.append(kind)
            }
        }

        let safeRequiresEmail = configuration.emailOptions.requiresEmail && configuration.emailOptions.allowsEmail
        let normalizedDefaultKind = distinctKinds.contains(configuration.kindOptions.defaultKind) ? configuration.kindOptions.defaultKind : distinctKinds[0]

        allowedKinds = distinctKinds
        defaultKind = normalizedDefaultKind
        showsKindPicker = configuration.kindOptions.showsKindPicker
        showsSeverityPicker = configuration.severityOptions.showsSeverityPicker
        defaultSeverity = configuration.severityOptions.defaultSeverity
        allowsEmail = configuration.emailOptions.allowsEmail
        self.requiresEmail = safeRequiresEmail
        allowsTechnicalDetails = configuration.technicalDetailsOptions.allowsTechnicalDetails
        technicalDetailsDefaultOn = configuration.technicalDetailsOptions.technicalDetailsDefaultOn
        allowsScreenshot = configuration.screenshotOptions.allowsScreenshot
        screenshotDefaultOn = configuration.screenshotOptions.screenshotDefaultOn
        requiresNotes = configuration.notesOptions.requiresNotes
    }

    public static let standard = FeedbackFormPolicy()

    public static let simpleIssue = FeedbackFormPolicy(
        .init(
            kindOptions: .init(allowedKinds: [.bug], defaultKind: .bug, showsKindPicker: false),
            severityOptions: .init(showsSeverityPicker: false),
            emailOptions: .init(allowsEmail: true, requiresEmail: false),
            technicalDetailsOptions: .init(technicalDetailsDefaultOn: false),
            screenshotOptions: .init(screenshotDefaultOn: false)
        )
    )

    public static let bugOnly = FeedbackFormPolicy(
        .init(
            kindOptions: .init(allowedKinds: [.bug], defaultKind: .bug, showsKindPicker: false),
            severityOptions: .init(showsSeverityPicker: false),
            technicalDetailsOptions: .init(allowsTechnicalDetails: true, technicalDetailsDefaultOn: true)
        )
    )

    public static let feedbackOnly = FeedbackFormPolicy(
        .init(
            kindOptions: .init(allowedKinds: [.feedback], defaultKind: .feedback, showsKindPicker: false),
            severityOptions: .init(showsSeverityPicker: false),
            emailOptions: .init(allowsEmail: false),
            technicalDetailsOptions: .init(allowsTechnicalDetails: false),
            screenshotOptions: .init(allowsScreenshot: false)
        )
    )

    public static let clientDebug = FeedbackFormPolicy(
        .init(
            kindOptions: .init(allowedKinds: [.bug], defaultKind: .bug, showsKindPicker: false),
            severityOptions: .init(showsSeverityPicker: true),
            technicalDetailsOptions: .init(allowsTechnicalDetails: true, technicalDetailsDefaultOn: true),
            screenshotOptions: .init(allowsScreenshot: true, screenshotDefaultOn: true)
        )
    )

    public var showsKindPickerWhenNeeded: Bool {
        allowedKinds.count > 1 && showsKindPicker
    }

    public func with(
        showsKindPicker: Bool? = nil,
        showsSeverityPicker: Bool? = nil,
        emailOptions: EmailOptions? = nil
    ) -> FeedbackFormPolicy {
        FeedbackFormPolicy(
            .init(
                kindOptions: .init(
                    allowedKinds: allowedKinds,
                    defaultKind: defaultKind,
                    showsKindPicker: showsKindPicker ?? self.showsKindPicker
                ),
                severityOptions: .init(
                    showsSeverityPicker: showsSeverityPicker ?? self.showsSeverityPicker,
                    defaultSeverity: defaultSeverity
                ),
                emailOptions: .init(
                    allowsEmail: emailOptions?.allowsEmail ?? allowsEmail,
                    requiresEmail: emailOptions?.requiresEmail ?? requiresEmail
                ),
                technicalDetailsOptions: .init(
                    allowsTechnicalDetails: allowsTechnicalDetails,
                    technicalDetailsDefaultOn: technicalDetailsDefaultOn
                ),
                screenshotOptions: .init(
                    allowsScreenshot: allowsScreenshot,
                    screenshotDefaultOn: screenshotDefaultOn
                ),
                notesOptions: .init(requiresNotes: requiresNotes)
            )
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
