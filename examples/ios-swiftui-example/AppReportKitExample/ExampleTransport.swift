import AppReportKit
import Foundation

final class ExampleTransport: AppReportTransport {
    func send(request _: URLRequest, body _: Data) async throws -> AppReportTransportResponse {
        AppReportTransportResponse(
            statusCode: 202,
            data: Data(#"{"ok":true}"#.utf8)
        )
    }
}
