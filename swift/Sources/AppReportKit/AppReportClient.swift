import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AppReportSubmissionResponse: Equatable {
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

public final class AppReportClient {
    private let endpointURL: URL
    private let appId: String
    private let bearerToken: String
    private let diagnosticsProvider: FeedbackDiagnosticsProvider?
    private let metadataProvider: FeedbackMetadataProviding
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
        self.metadataProvider = metadataProvider
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
        let report = FeedbackReport(
            appId: appId,
            kind: kind,
            severity: severity,
            notes: notes,
            email: email,
            metadata: metadataProvider.makeMetadata(screen: screen),
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
            appId: report.appId,
            kind: report.kind,
            severity: report.severity,
            notes: normalizedNotes,
            email: report.email?.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: report.metadata,
            diagnostics: report.diagnostics ?? [:],
            attachments: report.attachments
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

private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

