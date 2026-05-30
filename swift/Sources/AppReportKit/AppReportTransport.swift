import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AppReportTransportResponse {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol AppReportTransport {
    func send(request: URLRequest, body: Data) async throws -> AppReportTransportResponse
}

