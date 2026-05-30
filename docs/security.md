# Security notes

## Core model

- every client is treated as untrusted
- app bearer keys are revocable routing keys, not proof of user identity
- app config references secret binding names only; literal tokens do not belong in config
- the GitHub token exists only in Worker secrets
- the Swift package never talks to GitHub directly
- the Worker returns generic failures and does not expose policy internals
- local-only in-memory rate limiting and dedupe are not durable and are rejected by production config

## Recommended hardening

- use separate debug and production bearer keys
- rotate or revoke app keys if a build leaks one
- keep the issue target repository private
- optionally add certificate or public-key pinning in the host app with TrustKit or a custom `URLSessionDelegate`
- consider App Attest later if operational abuse warrants it

## Secret handling

Do not put any of these values in Swift code, examples, tests, fixtures, screenshots, or docs:

- GitHub tokens
- real bearer keys
- private repository URLs with embedded credentials
- `APP_CONFIG_JSON` values that inline secrets instead of binding names

## Privacy

- AppReportKit does not collect personal data by default.
- User email remains optional.
- Diagnostics content is controlled by the host app.
- Host apps are responsible for privacy disclosures, consent, and regional compliance.

## Attachment model

v1 is attachment-aware but not storage-first. Inline attachment data is size-limited and discarded after metadata rendering unless you add your own storage sink.
