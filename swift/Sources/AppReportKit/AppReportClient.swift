import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AppReportSubmissionResponse: Equatable, Sendable {
    public let accepted: Bool
    public let statusCode: Int

    public init(accepted: Bool, statusCode: Int) {
        self.accepted = accepted
        self.statusCode = statusCode
    }
}

public enum AppReportClientError: Error, Equatable {
    case emptyNotes
    case invalidResponse
    case serverRejected(statusCode: Int)
}

public final class AppReportClient: @unchecked Sendable {
    private let endpointURL: URL
    private let appId: String
    private let bearerToken: String
    private let diagnosticsProvider: FeedbackDiagnosticsProvider?
    private let reportBuilder: FeedbackReportBuilder
    private let transport: AppReportTransport

    public init(
        endpointURL: URL,
        appId: String,
        bearerToken: String,
        diagnosticsProvider: FeedbackDiagnosticsProvider? = nil,
        metadataProvider: FeedbackMetadataProviding = SystemFeedbackMetadataProvider(),
        transport: AppReportTransport = URLSessionTransport()
    ) {
        self.endpointURL = endpointURL
        self.appId = appId
        self.bearerToken = bearerToken
        self.diagnosticsProvider = diagnosticsProvider
        reportBuilder = FeedbackReportBuilder(appId: appId, metadataProvider: metadataProvider)
        self.transport = transport
    }

    public func submit(
        kind: FeedbackReportKind,
        notes: String,
        severity: FeedbackSeverity = .normal,
        email: String? = nil,
        screen: String? = nil,
        attachments: [FeedbackAttachment] = []
    ) async throws -> AppReportSubmissionResponse {
        let report = reportBuilder.makeReport(
            kind: kind,
            notes: notes,
            severity: severity,
            email: email,
            screen: screen,
            diagnostics: diagnosticsProvider?.makeDiagnostics() ?? [:],
            attachments: attachments
        )

        return try await submit(report)
    }

    public func submit(_ report: FeedbackReport) async throws -> AppReportSubmissionResponse {
        let normalizedNotes = report.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNotes.isEmpty else {
            throw AppReportClientError.emptyNotes
        }

        let normalizedReport = FeedbackReport(
            appId: appId,
            kind: report.kind,
            notes: normalizedNotes,
            metadata: report.metadata,
            submission: .init(
                severity: report.severity,
                email: report.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                diagnostics: report.diagnostics ?? [:],
                attachments: report.attachments,
                breadcrumbs: report.breadcrumbs
            )
        )

        let body = try jsonEncoder.encode(normalizedReport)
        let response = try await transport.send(request: makeRequest(), body: body)

        guard (200...299).contains(response.statusCode) else {
            throw AppReportClientError.serverRejected(statusCode: response.statusCode)
        }

        return AppReportSubmissionResponse(accepted: true, statusCode: response.statusCode)
    }

    private func makeRequest() -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

extension AppReportClient: FeedbackSubmitting {
    public func submit(_ request: FeedbackSubmissionRequest) async throws -> FeedbackSubmissionOutcome {
        var diagnostics = request.diagnostics
        if request.includeTechnicalDetails {
            diagnostics.merge(diagnosticsProvider?.makeDiagnostics() ?? [:]) { _, newValue in
                newValue
            }
        }

        let report = reportBuilder.makeReport(
            kind: request.kind,
            notes: request.notes,
            severity: request.severity,
            email: request.email,
            screen: request.screen,
            diagnostics: diagnostics,
            attachments: request.attachments + request.screenshotAttachments
        )

        let response = try await submit(report)
        return .submitted(response)
    }
}

private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()
