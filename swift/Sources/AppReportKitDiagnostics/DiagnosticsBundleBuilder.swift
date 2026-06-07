import AppReportKit
import Foundation

public struct DiagnosticsAttachment: Equatable, Sendable {
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

    init(screenshot: FeedbackScreenshot) {
        data = screenshot.data
        filename = screenshot.filename
        contentType = screenshot.contentType
        description = screenshot.description
    }

    func sanitizedFilename(fallback: String) -> String {
        let candidate = URL(fileURLWithPath: filename).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else {
            return fallback
        }

        return candidate
    }
}

public struct DiagnosticsBundleMaterialization: Equatable, Sendable {
    public let rootURL: URL
    public let fileAttachments: [FeedbackPreparedAttachment]
    public let shareItemURLs: [URL]

    public init(
        rootURL: URL,
        fileAttachments: [FeedbackPreparedAttachment],
        shareItemURLs: [URL]
    ) {
        self.rootURL = rootURL
        self.fileAttachments = fileAttachments
        self.shareItemURLs = shareItemURLs
    }
}

public struct DiagnosticsBundleBuilder {
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let harExporter: HARExporter

    public init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        harExporter: HARExporter = HARExporter()
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
        self.harExporter = harExporter
    }

    public func build(
        report: FeedbackReport,
        submittedAt: Date,
        networkEvents: [NetworkEvent],
        screenshots: [DiagnosticsAttachment]
    ) throws -> DiagnosticsBundleMaterialization {
        let rootURL = temporaryDirectory
            .appendingPathComponent("AppReportDiagnostics-\(timestampString(from: submittedAt))-\(UUID().uuidString)")
            .appendingPathExtension("bundle")

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let reportURL = rootURL.appendingPathComponent("report.json")
        let metadataURL = rootURL.appendingPathComponent("metadata.json")
        let readmeURL = rootURL.appendingPathComponent("README.txt")

        try writeReport(report, submittedAt: submittedAt, to: reportURL)
        try writeMetadata(report, to: metadataURL)
        try writeReadme(hasNetworkEvents: !networkEvents.isEmpty, screenshotCount: screenshots.count, to: readmeURL)

        var attachments = [
            FeedbackPreparedAttachment(fileURL: reportURL, contentType: "application/json"),
            FeedbackPreparedAttachment(fileURL: metadataURL, contentType: "application/json"),
            FeedbackPreparedAttachment(fileURL: readmeURL, contentType: "text/plain")
        ]

        if !networkEvents.isEmpty {
            let networkURL = rootURL.appendingPathComponent("network.har")
            try harExporter.export(networkEvents).write(to: networkURL)
            attachments.append(
                FeedbackPreparedAttachment(fileURL: networkURL, contentType: "application/json")
            )
        }

        if !screenshots.isEmpty {
            let screenshotsURL = rootURL.appendingPathComponent("screenshots", isDirectory: true)
            try fileManager.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
            var usedFilenames = Set<String>()

            for (index, screenshot) in screenshots.enumerated() {
                let sanitizedFilename = screenshot.sanitizedFilename(
                    fallback: "screenshot-\(index + 1).png"
                )
                let filename = uniqueFilename(
                    for: sanitizedFilename,
                    sequenceNumber: index + 1,
                    usedFilenames: &usedFilenames
                )
                let fileURL = screenshotsURL.appendingPathComponent(filename)
                try screenshot.data.write(to: fileURL)
                attachments.append(
                    FeedbackPreparedAttachment(fileURL: fileURL, contentType: screenshot.contentType)
                )
            }
        }

        return DiagnosticsBundleMaterialization(
            rootURL: rootURL,
            fileAttachments: attachments,
            shareItemURLs: attachments.map(\.fileURL)
        )
    }

    public func cleanup(_ materialization: DiagnosticsBundleMaterialization) throws {
        guard fileManager.fileExists(atPath: materialization.rootURL.path) else {
            return
        }

        try fileManager.removeItem(at: materialization.rootURL)
    }

    public func makeEndpointAttachments(from materialization: DiagnosticsBundleMaterialization) throws -> [FeedbackAttachment] {
        try materialization.fileAttachments.map { attachment in
            let data = try Data(contentsOf: attachment.fileURL)
            return FeedbackAttachment(
                filename: attachment.fileURL.lastPathComponent,
                contentType: attachment.contentType,
                data: data
            )
        }
    }

    private func writeReport(_ report: FeedbackReport, submittedAt: Date, to url: URL) throws {
        let payload = ReportPayload(
            kind: report.kind.rawValue,
            severity: report.severity.rawValue,
            notes: report.notes,
            email: report.email,
            diagnostics: report.diagnostics ?? [:],
            submittedAt: submittedAt
        )

        try encode(payload).write(to: url)
    }

    private func writeMetadata(_ report: FeedbackReport, to url: URL) throws {
        let payload = MetadataPayload(
            appId: report.appId,
            appVersion: report.metadata.appVersion,
            build: report.metadata.build,
            osName: report.metadata.osName,
            osVersion: report.metadata.osVersion,
            deviceModel: report.metadata.deviceModel,
            locale: report.metadata.locale,
            clientVersion: report.metadata.clientVersion
        )

        try encode(payload).write(to: url)
    }

    private func writeReadme(
        hasNetworkEvents: Bool,
        screenshotCount: Int,
        to url: URL
    ) throws {
        let lines = [
            "This diagnostics bundle was created by AppReportKitDiagnostics.",
            "",
            "Included items:",
            "- report details entered by the user",
            "- app and device metadata",
            hasNetworkEvents ? "- recent app-only network logs" : "- no network log file was included",
            screenshotCount > 0 ? "- host-supplied screenshots" : "- no screenshots were included",
            "",
            "Warnings:",
            "- logs may contain app interaction data",
            "- capture is app-only and not device-wide",
            "- no system proxy, root certificate, or MITM capture is used"
        ]

        let text = lines.joined(separator: "\n")
        try Data(text.utf8).write(to: url)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func uniqueFilename(
        for filename: String,
        sequenceNumber: Int,
        usedFilenames: inout Set<String>
    ) -> String {
        guard !usedFilenames.contains(filename) else {
            let fileExtension = URL(fileURLWithPath: filename).pathExtension
            let stem = URL(fileURLWithPath: filename)
                .deletingPathExtension()
                .lastPathComponent
            var duplicateIndex = 2

            while true {
                let candidateStem = stem.isEmpty ? "screenshot-\(sequenceNumber)" : stem
                let candidate = fileExtension.isEmpty
                    ? "\(candidateStem)-\(duplicateIndex)"
                    : "\(candidateStem)-\(duplicateIndex).\(fileExtension)"
                if usedFilenames.insert(candidate).inserted {
                    return candidate
                }
                duplicateIndex += 1
            }
        }

        usedFilenames.insert(filename)
        return filename
    }
}

private struct ReportPayload: Codable {
    let kind: String
    let severity: String
    let notes: String
    let email: String?
    let diagnostics: [String: String]
    let submittedAt: Date
}

private struct MetadataPayload: Codable {
    let appId: String
    let appVersion: String
    let build: String
    let osName: String
    let osVersion: String
    let deviceModel: String
    let locale: String
    let clientVersion: String
}
