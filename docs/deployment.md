# Deployment

## 1. Configure Worker variables

Set `APP_CONFIG_JSON` from `docs/worker-config.example.json`, adjusted for your apps and repositories.

The config stores only secret binding names such as `JUSTCARDS_PROD_REPORT_KEY`. It must not contain literal bearer token values or GitHub tokens.

## 2. Configure Worker secrets

Run these from `worker/`:

```bash
npx wrangler secret put GITHUB_TOKEN
npx wrangler secret put JUSTCARDS_PROD_REPORT_KEY
npx wrangler secret put JUSTCARDS_DEBUG_REPORT_KEY
```

Use one bearer key per app and environment. Treat them as revocable routing keys, not strong secrets.

## 3. Configure production bindings

Production mode must not use in-memory rate limiting or dedupe.

- bind the configured rate-limit binding named in each app's `rateLimit.bindingName`
- bind the configured KV namespace named in each app's `dedupe.bindingName`

The Worker expects the named rate-limit binding to expose a `limit({ key })` method that returns an object with either `allowed: boolean` or `success: boolean`. The named dedupe binding must be a KV namespace.

Example-only `wrangler.jsonc` KV shape:

```jsonc
{
  "kv_namespaces": [
    { "binding": "REPORT_DEDUPE_KV", "id": "your-kv-namespace-id" }
  ]
}
```

The exact Cloudflare configuration syntax for the rate-limit binding is product-specific and is not shipped here as a verified turnkey snippet. Keep the binding name aligned with `APP_CONFIG_JSON`, which defaults to `REPORT_RATE_LIMITER`.

If a production app requires a rate-limit or dedupe binding and the binding is missing or malformed, the Worker fails closed and returns a generic failure instead of creating an issue.

## 4. Install and deploy

```bash
npm install
npm run typecheck
npm test
npm run build
npx wrangler deploy
```

## 5. Point the Swift client at the Worker

Use the deployed `https://.../v1/report` URL in your app.

## 6. Scale one deployment across multiple apps

Use one Worker deployment and add one config entry per app/environment.

- one `appId` per app/environment
- one bearer secret per app/environment
- one `bearerKeyBinding` per entry pointing at that secret name
- one GitHub owner/repo target per entry
- one set of labels and policies per entry

Typical patterns:

1. Many apps into one private triage repo, using labels to split ownership.
2. Many apps into separate repos, using the same Worker deployment as the intake layer.

`docs/worker-config.example.json` shows the actual field names and binding names expected by the Worker runtime.

## 7. Deploy your own fork

1. Fork this repository.
2. Create a private GitHub intake repository.
3. Create a fine-grained GitHub token with **Metadata: read-only** and **Issues: read and write**.
4. Create the Cloudflare Worker and its KV/rate-limit bindings.
5. Set `GITHUB_TOKEN` and one per-app report key secret per app/environment.
6. Edit `APP_CONFIG_JSON`.
7. Run the worker validation commands.
8. Deploy and point your Swift client at the Worker URL.

## 8. Local development and tests

Local development and tests may use the in-memory rate-limit and dedupe implementations by setting `runtimeMode` to `local`.
