# AppReportKit

Small in-app bug reports and feature requests for Swift apps.

It is not a hosted platform. It is a Cloudflare Worker plus a Swift package that sends reports to private GitHub issues.

## What It Is

- `worker/` receives reports at `POST /v1/report`
- `swift/` contains:
  - `AppReportKit`
  - `AppReportKitUI`
  - `AppReportKitDiagnostics`

The normal flow is:

1. Your app submits a report.
2. The Worker validates it, rate-limits it, and deduplicates obvious repeats.
3. The Worker creates a private GitHub issue with a server-side token.

## What It Is Not

- no dashboard
- no accounts
- no analytics
- no crash reporting
- no app-side GitHub token
- no SaaS control plane

## Swift Package

`AppReportKit` is the core client.

`AppReportKitUI` adds a reusable SwiftUI feedback form.

`AppReportKitDiagnostics` is optional. It is for TestFlight or client debugging when you want to attach app-scoped technical detail without proxy setup, MITM tooling, or device-wide capture.

## Quick Start

```swift
import AppReportKit
import AppReportKitUI

let client = AppReportClient(
    endpointURL: URL(string: "https://reports.example.com/v1/report")!,
    appId: "justcards",
    bearerToken: "APP_REPORT_KEY_PLACEHOLDER"
)

FeedbackForm(client: client, screenContext: "InvoiceEditor")
```

If you do not want the built-in form, call `client.submit(...)` directly.

## Diagnostics

Use `AppReportKitDiagnostics` when a tester needs to send a useful bug report with notes, metadata, screenshots, and recent app-only network activity.

Important boundaries:

- capture is app-only
- no global interception
- no proxying
- no root certificates
- no TLS trust changes
- no device-wide traffic capture

That module can also prepare email/share delivery when no Worker endpoint is configured.

See [docs/diagnostics.md](docs/diagnostics.md).

## Worker Setup

The Worker expects:

- `APP_CONFIG_JSON` as a normal Worker variable
- `GITHUB_TOKEN` as a Worker secret
- one Worker secret per app/environment report key

Typical deploy flow:

```bash
cd worker
npm install
npx wrangler secret put GITHUB_TOKEN
npx wrangler secret put JUSTCARDS_PROD_REPORT_KEY
npx wrangler deploy
```

The Worker config shape lives in [docs/worker-config.example.json](docs/worker-config.example.json).

## Boundaries

- attachments are small and optional
- diagnostics bundle upload to the Worker is off by default
- screenshots are host-supplied only
- host apps own privacy disclosure and consent
- bearer keys are routing keys, not user identity

## Docs

- [docs/deployment.md](docs/deployment.md)
- [docs/diagnostics.md](docs/diagnostics.md)
- [docs/security.md](docs/security.md)
- [docs/worker-config.example.json](docs/worker-config.example.json)
- [examples/ios-swiftui-example/README.md](examples/ios-swiftui-example/README.md)
