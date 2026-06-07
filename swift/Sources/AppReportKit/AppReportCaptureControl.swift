import Foundation

package enum AppReportCaptureControl {
    package static let diagnosticsExclusionRequestPropertyKey =
        "com.appreportkit.diagnostics.capture.exclude"

    package static func excludingDiagnosticsCapture(_ request: URLRequest) -> URLRequest {
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(
            true,
            forKey: diagnosticsExclusionRequestPropertyKey,
            in: mutableRequest
        )
        return mutableRequest as URLRequest
    }

    package static func isExcludedFromDiagnosticsCapture(_ request: URLRequest) -> Bool {
        (URLProtocol.property(
            forKey: diagnosticsExclusionRequestPropertyKey,
            in: request
        ) as? Bool) == true
    }
}
