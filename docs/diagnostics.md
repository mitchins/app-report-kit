# Diagnostics add-on

`AppReportKitDiagnostics` is an optional add-on for client and TestFlight debugging.

It captures only app-owned traffic sent through a `URLSessionConfiguration` the host app explicitly installs, or through manual wrapper calls the host app opts into. It does not install certificates, proxy traffic, capture device-wide requests, or perform MITM interception.

## What it adds

- app-only network recording through a provided `URLSessionConfiguration`
- case-insensitive redaction for common secret keys
- rolling in-memory retention
- practical HAR 1.2 export at `network.har`
- diagnostics bundle export with report, metadata, HAR, screenshots, and README
- email/share preparation when no endpoint is configured
- optional `FeedbackForm` hooks for technical details and screenshots

## What it does not add

- global `URLSession` interception
- `URLProtocol.registerClass`
- device-wide traffic capture
- proxy setup
- root certificates
- TLS trust changes
- Netfox-style viewers
- automatic silent uploads
- server-side HAR parsing
- server-side decryption

## Bundle contents

The bundle is materialized as a temporary directory:

```text
AppReportDiagnostics-<timestamp>.bundle/
  report.json
  metadata.json
  network.har
  screenshots/
  README.txt
```

`network.har` is included only when technical details are enabled and recorded events exist.

Screenshots are included only when the host app supplies them.

## Email/share-only TestFlight flow

Use this when there is no Worker endpoint in the build.

```swift
import AppReportKit
import AppReportKitUI
import AppReportKitDiagnostics

let recorder = NetworkRecorder()
let submitter = AppReportDiagnosticsSubmitter(
    reportBuilder: FeedbackReportBuilder(appId: "justcards"),
    delivery: .email(.standard(recipient: "support@example.com", appName: "JustCards")),
    support: .init(
        networkRecorder: recorder,
        screenshotProvider: MyScreenshotProvider()
    )
)

FeedbackForm(
    submitter: submitter,
    screenContext: "InvoiceEditor",
    deliveryHandler: { pendingDelivery in
        defer {
            try? DiagnosticsDeliveryCleanup.cleanup(pendingDelivery)
        }

        switch pendingDelivery {
        case let .email(emailDraft):
            // Present MFMailComposeViewController in the host app.
            // Use emailDraft.recipients, subject, body, and attachments.
            return true
        case let .share(shareDraft):
            // Present a share/export UI in the host app.
            // Use shareDraft.itemURLs.
            return true
        }
    }
)
```

On iOS the diagnostics submitter checks `MFMailComposeViewController.canSendMail()` before choosing a mail draft. If mail is unavailable it returns a share/export draft instead.

On macOS `email(...)` resolves to export/share only. It does not use `mailto:`.

`temporaryDirectoryURL` remains valid until the host finishes presenting the mail/share flow. The host should then remove the exported files. `DiagnosticsDeliveryCleanup.cleanup(_:)` is the provided helper for that.

## Worker endpoint behavior

Diagnostics bundle upload to the Worker is off by default.

- endpoint mode can still include small host-supplied screenshot attachments if the host app opts in
- endpoint mode does not attach the diagnostics bundle unless explicitly configured
- if attached, the Worker treats diagnostics files as opaque attachments and existing attachment limits still apply

This keeps the current Worker scope bounded. There is no storage, bundle parsing, or HAR analysis on the server side.

## Recommended network capture setup

Install capture on the `URLSessionConfiguration` your app or networking library already uses.

```swift
import AppReportKitDiagnostics

let recorder = NetworkRecorder(policy: .metadataOnly)
let configuration = URLSessionConfiguration.default
AppReportNetworkCapture.install(on: configuration, recorder: recorder)

let session = URLSession(configuration: configuration)
```

For Alamofire and similar libraries, install once on the configuration you pass into the client:

```swift
import Alamofire
import AppReportKitDiagnostics

let recorder = NetworkRecorder(policy: .metadataOnly)
let configuration = URLSessionConfiguration.default
AppReportNetworkCapture.install(on: configuration, recorder: recorder)

let session = Alamofire.Session(configuration: configuration)
```

This captures requests made by any `URLSession` built from that configuration. It does not capture traffic from libraries that create their own private session/configuration outside that install point.

## Manual escape hatch

If a host app needs per-call control, the explicit wrapper path is still available.

```swift
import AppReportKitDiagnostics

let recorder = NetworkRecorder()
let instrumentedSession = InstrumentedURLSession(
    session: URLSession(configuration: .ephemeral),
    recorder: recorder
)

var request = URLRequest(url: URL(string: "https://api.example.com/orders")!)
request.httpMethod = "GET"

let (data, response) = try await instrumentedSession.data(
    for: request,
    taskMetadata: ["feature": "orders-list"]
)
```

You can also wrap an API client or transport abstraction directly by calling `recorder.capture(request:taskMetadata:operation:)`.

## Privacy and disclosure

- capture is app-only, not device-wide
- redaction reduces exposure but is not a guarantee
- text-body previews scrub obvious token shapes, but malformed JSON or unusual payload formats may still require previews to stay off
- logs may still contain app interaction data
- host apps must disclose diagnostics collection where their privacy policy or local law requires it
- email/share is less controlled than the Worker path and is intended for deliberate support/debugging workflows
- encryption is future scope for higher-risk apps
