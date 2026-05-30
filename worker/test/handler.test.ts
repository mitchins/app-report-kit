import { describe, expect, it } from 'vitest';

import { ConfiguredDuplicateStore, MemoryDuplicateStore } from '../src/dedupe-store';
import { buildFingerprint } from '../src/fingerprint';
import { processRequest } from '../src/handler';
import { ConfiguredRateLimiter, MemoryRateLimiter } from '../src/rate-limit';

import type {
  DuplicateStore,
  Env,
  GitHubIssueClient,
  IssueCreationRequest,
  KVNamespaceLike,
  RateLimitBinding,
  RateLimiter,
  ReportPayload,
  ReportEnrichmentProvider
} from '../src/types';

class FakeGitHubIssueClient implements GitHubIssueClient {
  public readonly calls: IssueCreationRequest[] = [];

  constructor(private readonly shouldFail = false) {}

  async createIssue(request: IssueCreationRequest) {
    if (this.shouldFail) {
      throw new Error('github exploded');
    }

    this.calls.push(request);
    return {
      issueNumber: 101,
      htmlUrl: 'https://github.com/octocat/private-intake/issues/101'
    };
  }
}

class AllowingRateLimitBinding implements RateLimitBinding {
  async limit() {
    return { allowed: true };
  }
}

class MemoryKVNamespace implements KVNamespaceLike {
  private readonly values = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.values.get(key) ?? null;
  }

  async put(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }
}

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    APP_CONFIG_JSON: JSON.stringify({
      runtimeMode: 'local',
      apps: [
        {
          appId: 'justcards',
          bearerKeyBinding: 'JUSTCARDS_PROD_REPORT_KEY',
          github: {
            owner: 'octocat',
            repo: 'private-intake'
          },
          defaultLabels: ['team:solo'],
          allowedKinds: ['bug', 'feature', 'feedback'],
          maxPayloadSizeBytes: 4_096,
          rateLimit: {
            mode: 'memory',
            windowSeconds: 60,
            maxRequests: 2
          },
          attachmentPolicy: {
            maxAttachmentBytes: 2_048,
            maxAttachmentCount: 2,
            allowInlineData: true,
            allowRemoteUrls: true
          },
          dedupe: {
            mode: 'memory',
            windowSeconds: 3_600
          }
        }
      ]
    }),
    GITHUB_TOKEN: 'TEST_GITHUB_TOKEN',
    JUSTCARDS_PROD_REPORT_KEY: 'TEST_APP_REPORT_KEY',
    ...overrides
  };
}

function makeProductionEnv(overrides: Partial<Env> = {}): Env {
  return makeEnv({
    APP_CONFIG_JSON: JSON.stringify({
      runtimeMode: 'production',
      apps: [
        {
          appId: 'justcards',
          bearerKeyBinding: 'JUSTCARDS_PROD_REPORT_KEY',
          github: {
            owner: 'octocat',
            repo: 'private-intake'
          },
          defaultLabels: ['team:solo'],
          allowedKinds: ['bug', 'feature', 'feedback'],
          maxPayloadSizeBytes: 4_096,
          rateLimit: {
            mode: 'binding',
            windowSeconds: 60,
            maxRequests: 2,
            bindingName: 'REPORT_RATE_LIMITER'
          },
          attachmentPolicy: {
            maxAttachmentBytes: 2_048,
            maxAttachmentCount: 2,
            allowInlineData: true,
            allowRemoteUrls: true
          },
          dedupe: {
            mode: 'kv',
            windowSeconds: 3_600,
            bindingName: 'REPORT_DEDUPE_KV'
          }
        }
      ]
    }),
    ...overrides
  });
}

function makePayload(overrides: Record<string, unknown> = {}): ReportPayload {
  const samplePat = [['g', 'h', 'p'].join(''), '_', 'A'.repeat(32)].join('');
  return {
    appId: 'justcards',
    kind: 'bug',
    severity: 'normal',
    notes: 'Export fails from invoice editor\n1. Tap Export\n2. Select PDF',
    email: 'user@example.com',
    metadata: {
      appVersion: '1.2.3',
      build: '42',
      osName: 'iOS',
      osVersion: '18.5',
      deviceModel: 'iPhone16,2',
      locale: 'en-AU',
      clientVersion: '0.1.0',
      screen: 'InvoiceEditor'
    },
    diagnostics: {
      lastAction: 'Tapped Export',
      redactedHeader: `Authorization: Bearer ${samplePat}`
    },
    attachments: [
      {
        filename: 'screenshot.png',
        contentType: 'image/png',
        byteCount: 128,
        dataBase64: 'aGVsbG8='
      }
    ],
    ...overrides
  };
}

function makeRequest(payload: unknown, options: { auth?: string; ip?: string; method?: string; path?: string } = {}) {
  const headers = new Headers({
    'content-type': 'application/json',
    'CF-Connecting-IP': options.ip ?? '198.51.100.10'
  });

  if (options.auth !== undefined) {
    headers.set('authorization', `Bearer ${options.auth}`);
  }

  return new Request(`https://reports.example.com${options.path ?? '/v1/report'}`, {
    method: options.method ?? 'POST',
    headers,
    body: JSON.stringify(payload)
  });
}

function makeDependencies(input: {
  githubClient?: FakeGitHubIssueClient;
  rateLimiter?: RateLimiter;
  duplicateStore?: DuplicateStore;
  now?: () => Date;
}) {
  return {
    githubClient: input.githubClient ?? new FakeGitHubIssueClient(),
    rateLimiter: input.rateLimiter ?? new MemoryRateLimiter(() => Date.parse('2026-05-30T00:00:00.000Z')),
    duplicateStore:
      input.duplicateStore ??
      new MemoryDuplicateStore(() => Date.parse('2026-05-30T00:00:00.000Z')),
    enrichmentProvider: {
      async enrich() {
        return null;
      }
    } satisfies ReportEnrichmentProvider,
    now: input.now ?? (() => new Date('2026-05-30T00:00:00.000Z'))
  };
}

async function expectGenericFailure(status: number, response: Response) {
  const body = await response.text();
  expect(response.status).toBe(status);
  expect(body).toBe('{"ok":false,"error":"Request could not be accepted."}');
}

describe('processRequest', () => {
  it('accepts a valid report and creates exactly one GitHub issue', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('accepted');
    expect(result.githubAttempted).toBe(true);
    expect(result.issueCreated).toBe(true);
    expect(result.response.status).toBe(202);
    expect(githubClient.calls).toHaveLength(1);
  });

  it('never creates a GitHub issue for missing auth', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload(), { auth: undefined }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_missing_auth');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(401, result.response);
  });

  it('never creates a GitHub issue for an invalid bearer key', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'WRONG_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_invalid_auth');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(401, result.response);
  });

  it('never creates a GitHub issue for a malformed bearer header', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY extra' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_missing_auth');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(401, result.response);
  });

  it('never creates a GitHub issue for an unknown app id', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload({ appId: 'ghost-app' }), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_unknown_app');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(401, result.response);
  });

  it('never creates a GitHub issue for missing notes', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload({ notes: '   ' }), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_missing_notes');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(400, result.response);
  });

  it('never creates a GitHub issue for an invalid report kind', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload({ kind: 'support' }), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_invalid_kind');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(400, result.response);
  });

  it('never creates a GitHub issue for an oversized payload', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload({ notes: 'x'.repeat(10_000) }), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_oversized_payload');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(413, result.response);
  });

  it('never creates a GitHub issue for an oversized attachment', async () => {
    const githubClient = new FakeGitHubIssueClient();
    const payload = makePayload({
      attachments: [
        {
          filename: 'screenshot.png',
          contentType: 'image/png',
          byteCount: 4_096,
          dataBase64: 'aGVsbG8='
        }
      ]
    });

    const result = await processRequest(
      makeRequest(payload, { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('rejected_oversized_attachment');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(413, result.response);
  });

  it('creates the expected GitHub issue title, labels, and sanitized body', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient })
    );

    expect(result.category).toBe('accepted');
    expect(githubClient.calls[0]?.title).toBe('[justcards][Bug] Export fails from invoice editor');
    expect(githubClient.calls[0]?.labels).toEqual([
      'team:solo',
      'source:in-app',
      'app:justcards',
      'kind:bug',
      'severity:normal',
      'platform:ios'
    ]);
    expect(githubClient.calls[0]?.body).toContain('[REDACTED_SECRET]');
    expect(githubClient.calls[0]?.body).not.toContain('TEST_APP_REPORT_KEY');
    expect(githubClient.calls[0]?.body).not.toContain('TEST_GITHUB_TOKEN');
    expect(githubClient.calls[0]?.body).not.toContain('198.51.100.10');
  });

  it('generates a stable dedupe fingerprint and normalizes whitespace and case', async () => {
    const first = makePayload();
    const second = makePayload({
      notes: ' export   FAILS from invoice editor  \n 1. Tap Export \n2. Select PDF ',
      metadata: {
        ...makePayload().metadata,
        osName: 'ios'
      }
    });

    expect(await buildFingerprint(first)).toBe(await buildFingerprint(second));
  });

  it('treats duplicate requests as accepted without creating another GitHub issue', async () => {
    const githubClient = new FakeGitHubIssueClient();
    const duplicateStore = new MemoryDuplicateStore(() => Date.parse('2026-05-30T00:00:00.000Z'));

    const first = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient, duplicateStore })
    );
    const second = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient, duplicateStore })
    );

    expect(first.category).toBe('accepted');
    expect(second.category).toBe('accepted_duplicate');
    expect(second.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(1);
    expect(second.response.status).toBe(202);
  });

  it('blocks repeated abusive submissions before GitHub issue creation', async () => {
    const githubClient = new FakeGitHubIssueClient();
    const rateLimiter = new MemoryRateLimiter(() => Date.parse('2026-05-30T00:00:00.000Z'));
    const env = makeEnv({
      APP_CONFIG_JSON: JSON.stringify({
        runtimeMode: 'local',
        apps: [
          {
            appId: 'justcards',
            bearerKeyBinding: 'JUSTCARDS_PROD_REPORT_KEY',
            github: {
              owner: 'octocat',
              repo: 'private-intake'
            },
            defaultLabels: [],
            allowedKinds: ['bug', 'feature', 'feedback'],
            maxPayloadSizeBytes: 4_096,
            rateLimit: {
              mode: 'memory',
              windowSeconds: 60,
              maxRequests: 1
            },
            attachmentPolicy: {
              maxAttachmentBytes: 2_048,
              maxAttachmentCount: 2,
              allowInlineData: true,
              allowRemoteUrls: true
            },
            dedupe: {
              mode: 'memory',
              windowSeconds: 1
            }
          }
        ]
      })
    });

    const first = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      env,
      makeDependencies({ githubClient, rateLimiter })
    );
    const second = await processRequest(
      makeRequest(
        makePayload({ notes: 'A different report body so dedupe does not trigger first.' }),
        { auth: 'TEST_APP_REPORT_KEY' }
      ),
      env,
      makeDependencies({ githubClient, rateLimiter })
    );

    expect(first.category).toBe('accepted');
    expect(second.category).toBe('rejected_rate_limited');
    expect(second.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(1);
    expect(second.response.headers.get('retry-after')).toBe('60');
    await expectGenericFailure(429, second.response);
  });

  it('fails closed when production rate-limit binding is required but missing', async () => {
    const githubClient = new FakeGitHubIssueClient();
    const env = makeProductionEnv({
      REPORT_DEDUPE_KV: new MemoryKVNamespace()
    });

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      env,
      makeDependencies({
        githubClient,
        rateLimiter: new ConfiguredRateLimiter(env)
      })
    );

    expect(result.category).toBe('failed_rate_limit_unavailable');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(503, result.response);
  });

  it('fails closed when production dedupe binding is required but missing', async () => {
    const githubClient = new FakeGitHubIssueClient();

    const env = makeProductionEnv({
      REPORT_RATE_LIMITER: new AllowingRateLimitBinding()
    });

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      env,
      makeDependencies({
        githubClient,
        rateLimiter: new ConfiguredRateLimiter(env),
        duplicateStore: new ConfiguredDuplicateStore(env)
      })
    );

    expect(result.category).toBe('failed_dedupe_unavailable');
    expect(result.githubAttempted).toBe(false);
    expect(githubClient.calls).toHaveLength(0);
    await expectGenericFailure(503, result.response);
  });

  it('uses configured KV dedupe storage in production without creating duplicate issues', async () => {
    const githubClient = new FakeGitHubIssueClient();
    const env = makeProductionEnv({
      REPORT_RATE_LIMITER: new AllowingRateLimitBinding(),
      REPORT_DEDUPE_KV: new MemoryKVNamespace()
    });
    const duplicateStore = new ConfiguredDuplicateStore(env);
    const dependencies = makeDependencies({
      githubClient,
      rateLimiter: new ConfiguredRateLimiter(env),
      duplicateStore
    });

    const first = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      env,
      dependencies
    );
    const second = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      env,
      dependencies
    );

    expect(first.category).toBe('accepted');
    expect(second.category).toBe('accepted_duplicate');
    expect(githubClient.calls).toHaveLength(1);
  });

  it('keeps the client response successful when dedupe persistence fails after issue creation', async () => {
    const githubClient = new FakeGitHubIssueClient();
    const duplicateStore: DuplicateStore = {
      async findRecent() {
        return null;
      },
      async record() {
        throw new Error('dedupe persistence unavailable');
      }
    };

    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient, duplicateStore })
    );

    expect(result.category).toBe('accepted_without_dedupe_record');
    expect(result.githubAttempted).toBe(true);
    expect(result.issueCreated).toBe(true);
    expect(result.response.status).toBe(202);
    expect(githubClient.calls).toHaveLength(1);
  });

  it('maps GitHub API failures to a safe generic response with an internal category', async () => {
    const result = await processRequest(
      makeRequest(makePayload(), { auth: 'TEST_APP_REPORT_KEY' }),
      makeEnv(),
      makeDependencies({ githubClient: new FakeGitHubIssueClient(true) })
    );

    expect(result.category).toBe('failed_github');
    expect(result.githubAttempted).toBe(true);
    await expectGenericFailure(502, result.response);
  });
});
