import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct URLSessionTransport: AppReportTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(request: URLRequest, body: Data) async throws -> AppReportTransportResponse {
        var request = AppReportCaptureControl.excludingDiagnosticsCapture(request)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppReportClientError.invalidResponse
        }

        return AppReportTransportResponse(statusCode: httpResponse.statusCode, data: data)
    }
}
