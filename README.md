# AppReportKit

Lightweight in-app bug reports and feature requests, routed through Cloudflare Workers to private GitHub issues.

AppReportKit is a small intake pipe for solo developers shipping multiple Swift apps. Native apps submit bug reports, feature requests, and general feedback to a Cloudflare Worker. The Worker validates, rate-limits, deduplicates, and creates structured private GitHub issues with a server-side token.

## What ships in v1

1. `worker/` — a TypeScript Cloudflare Worker with `POST /v1/report`
2. `swift/` — a Swift package with `AppReportKit` and `AppReportKitUI`

## Non-goals

- dashboard
- accounts or login
- analytics
- crash reporting
- app-side GitHub access
- mandatory screenshot storage
- mandatory certificate pinning
- AI triage by default
- heavy theming or design system work

## Worker features

- per-app bearer key auth
- bearer key config references Worker secret binding names only
- schema validation
- required notes field
- payload and attachment size limits
- rate limiting by app key identity and hashed client IP
- deterministic dedupe fingerprint
- obvious secret redaction
- GitHub issue creation with server-side token only
- generic client-safe responses
- multiple app configs

## Swift package features

- async/await client API
- `AppReportKit` works without `AppReportKitUI`
- injectable endpoint URL, app ID, bearer token, diagnostics provider, metadata provider, and transport
- automatic metadata collection for version, build, platform, device model, locale, and package version
- optional email field
- optional attachment payload support
- reusable SwiftUI `FeedbackForm`
- injectable `FeedbackFormCopy` for labels, placeholders, and success/error text
- minimal styling hooks

## Repository layout

```text
app-report-kit/
  README.md
  LICENSE
  PLAN.md
  worker/
  swift/
  examples/
  docs/
  .github/workflows/
```

## Exact setup steps for a new app

1. Add the Swift package from this repository to your app target.
2. Create a per-app or per-environment bearer key for the Worker, for example `JUSTCARDS_PROD_REPORT_KEY`.
3. Initialize `AppReportClient` with your Worker endpoint, app ID, and bearer key.
4. Present `FeedbackForm(client:)` or call `client.submit(...)` directly.

```swift
import AppReportKit
import AppReportKitUI

let client = AppReportClient(
    endpointURL: URL(string: "https://reports.example.com/v1/report")!,
    appId: "justcards",
    bearerToken: "APP_REPORT_KEY_PLACEHOLDER",
    diagnosticsProvider: MyDiagnosticsProvider()
)

FeedbackForm(client: client, screenContext: "InvoiceEditor")
```

If you need light copy changes without rebuilding the form, inject `FeedbackFormCopy`:

```swift
FeedbackForm(
    client: client,
    screenContext: "InvoiceEditor",
    copy: FeedbackFormCopy(
        notesLabel: "What happened?",
        notesPlaceholder: "Share the steps, expected result, and actual result."
    )
)
```

## Exact setup steps for Cloudflare Worker secrets

`APP_CONFIG_JSON` is a normal Worker variable. The GitHub token and per-app report keys come only from Worker secrets. Production rate limiting and dedupe also require durable bindings referenced by name from `APP_CONFIG_JSON`.

```bash
cd worker
npm install
npx wrangler secret put GITHUB_TOKEN
npx wrangler secret put JUSTCARDS_PROD_REPORT_KEY
npx wrangler deploy
```

Set `APP_CONFIG_JSON` to JSON matching `docs/worker-config.example.json`, then bind the named production rate-limit and KV dedupe resources in `wrangler.jsonc` or your deployment environment.

## Scaling multiple apps

One Worker deployment can route reports for many apps.

- use one `appId` per app and environment
- use one bearer secret per app and environment
- map `appId -> bearerKeyBinding -> GitHub owner/repo/defaultLabels/policies` in `APP_CONFIG_JSON`
- keep debug and production entries separate so keys and rate limits can be revoked independently

Example: multiple apps into one private triage repo:

```json
{
  "runtimeMode": "production",
  "apps": [
    {
      "appId": "justcards-ios-prod",
      "bearerKeyBinding": "JUSTCARDS_IOS_PROD_REPORT_KEY",
      "github": { "owner": "your-org", "repo": "private-triage" },
      "defaultLabels": ["app:justcards", "platform:ios"],
      "allowedKinds": ["bug", "feature", "feedback"],
      "maxPayloadSizeBytes": 32768,
      "rateLimit": { "mode": "binding", "windowSeconds": 3600, "maxRequests": 6, "bindingName": "REPORT_RATE_LIMITER" },
      "attachmentPolicy": { "maxAttachmentBytes": 262144, "maxAttachmentCount": 2, "allowInlineData": true, "allowRemoteUrls": true },
      "dedupe": { "mode": "kv", "windowSeconds": 86400, "bindingName": "REPORT_DEDUPE_KV" }
    },
    {
      "appId": "recipebox-macos-prod",
      "bearerKeyBinding": "RECIPEBOX_MACOS_PROD_REPORT_KEY",
      "github": { "owner": "your-org", "repo": "private-triage" },
      "defaultLabels": ["app:recipebox", "platform:macos"],
      "allowedKinds": ["bug", "feature", "feedback"],
      "maxPayloadSizeBytes": 32768,
      "rateLimit": { "mode": "binding", "windowSeconds": 3600, "maxRequests": 6, "bindingName": "REPORT_RATE_LIMITER" },
      "attachmentPolicy": { "maxAttachmentBytes": 262144, "maxAttachmentCount": 2, "allowInlineData": true, "allowRemoteUrls": true },
      "dedupe": { "mode": "kv", "windowSeconds": 86400, "bindingName": "REPORT_DEDUPE_KV" }
    }
  ]
}
```

Example: multiple apps into separate private repos:

```json
{
  "runtimeMode": "production",
  "apps": [
    {
      "appId": "justcards-prod",
      "bearerKeyBinding": "JUSTCARDS_PROD_REPORT_KEY",
      "github": { "owner": "your-org", "repo": "justcards-intake" },
      "defaultLabels": ["app:justcards"],
      "allowedKinds": ["bug", "feature", "feedback"],
      "maxPayloadSizeBytes": 32768,
      "rateLimit": { "mode": "binding", "windowSeconds": 3600, "maxRequests": 6, "bindingName": "REPORT_RATE_LIMITER" },
      "attachmentPolicy": { "maxAttachmentBytes": 262144, "maxAttachmentCount": 2, "allowInlineData": true, "allowRemoteUrls": true },
      "dedupe": { "mode": "kv", "windowSeconds": 86400, "bindingName": "REPORT_DEDUPE_KV" }
    },
    {
      "appId": "recipebox-prod",
      "bearerKeyBinding": "RECIPEBOX_PROD_REPORT_KEY",
      "github": { "owner": "your-org", "repo": "recipebox-intake" },
      "defaultLabels": ["app:recipebox"],
      "allowedKinds": ["bug", "feature", "feedback"],
      "maxPayloadSizeBytes": 32768,
      "rateLimit": { "mode": "binding", "windowSeconds": 3600, "maxRequests": 6, "bindingName": "REPORT_RATE_LIMITER" },
      "attachmentPolicy": { "maxAttachmentBytes": 262144, "maxAttachmentCount": 2, "allowInlineData": true, "allowRemoteUrls": true },
      "dedupe": { "mode": "kv", "windowSeconds": 86400, "bindingName": "REPORT_DEDUPE_KV" }
    }
  ]
}
```

## Deploy your own fork

1. Create a private GitHub repository that will receive the Worker-created issues.
2. Create a fine-grained GitHub token scoped to that repo with **Metadata: read-only** and **Issues: read and write**.
3. Create a Cloudflare Worker for your fork.
4. Configure a KV namespace for `REPORT_DEDUPE_KV` and a rate-limit binding for `REPORT_RATE_LIMITER`.
5. Set Worker secrets for `GITHUB_TOKEN` and one per-app report key secret such as `JUSTCARDS_PROD_REPORT_KEY`.
6. Edit `APP_CONFIG_JSON` so each app entry points at the correct `appId`, bearer key binding name, GitHub owner/repo, labels, and policies.
7. Deploy the Worker.
8. Configure the Swift client with your Worker URL, `appId`, and the matching per-app report key.

## Exact GitHub token permissions needed

Use a fine-grained personal access token or GitHub App token scoped to the private intake repository only.

| Permission | Access |
| --- | --- |
| Metadata | Read-only |
| Issues | Read and write |

No app-side code, docs, fixtures, or examples should ever contain the GitHub token.

## v1 limitations

- local/test config may use in-memory rate-limit and dedupe stores, but production config must use binding-backed rate limiting and KV-backed dedupe
- attachments are accepted only as metadata or small inline payloads and are not stored by default
- the bundled SwiftUI form does not capture screenshots automatically
- TrustKit or other pinning is optional and app-owned

## Privacy notes

- no personal data is collected by default
- email is optional and only sent when the host app includes it
- diagnostics are supplied by the host app and are not collected automatically beyond basic app/device metadata
- host apps are responsible for their own privacy disclosures and consent flows
- bearer keys are revocable routing and rate-limit keys, not strong secrets or proof of user identity

## Docs

- `docs/deployment.md`
- `docs/security.md`
- `docs/worker-config.example.json`
- `examples/ios-swiftui-example/README.md`
