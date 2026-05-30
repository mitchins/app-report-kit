# iOS SwiftUI example

```swift
import AppReportKit
import AppReportKitUI
import SwiftUI

struct SupportView: View {
    private let client = AppReportClient(
        endpointURL: URL(string: "https://reports.example.com/v1/report")!,
        appId: "justcards",
        bearerToken: "APP_REPORT_KEY_PLACEHOLDER",
        diagnosticsProvider: ExampleDiagnosticsProvider()
    )

    var body: some View {
        FeedbackForm(
            client: client,
            initialKind: .bug,
            showsSeverityPicker: true,
            screenContext: "InvoiceEditor"
        )
    }
}

struct ExampleDiagnosticsProvider: FeedbackDiagnosticsProvider {
    func makeDiagnostics() -> [String: String] {
        [
            "lastAction": "Tapped Export"
        ]
    }
}
```

Use the core module directly if you do not want the packaged form:

```swift
let response = try await client.submit(
    kind: .feedback,
    notes: "Would love a bigger type scale in settings.",
    severity: .normal
)
```
