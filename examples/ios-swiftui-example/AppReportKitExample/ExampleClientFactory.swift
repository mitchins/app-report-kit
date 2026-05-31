import AppReportKit
import Foundation

enum ExampleClientFactory {
    static func makeClient() -> AppReportClient {
        AppReportClient(
            endpointURL: URL(string: "https://reports.example.com/v1/report")!,
            appId: "justcards",
            bearerToken: "EXAMPLE_APP_REPORT_KEY",
            diagnosticsProvider: ExampleDiagnosticsProvider(),
            transport: ExampleTransport()
        )
    }
}

private struct ExampleDiagnosticsProvider: FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String] {
        [
            "lastAction": "Tapped Export"
        ]
    }
}
