import { describe, expect, it } from 'vitest';

import { renderIssueBody } from '../src/issue-renderer';
import { redactReportSecrets } from '../src/redaction';

import type { AppConfig, ReportPayload } from '../src/types';

const appConfig: AppConfig = {
  appId: 'justcards',
  bearerKeyBinding: 'JUSTCARDS_PROD_REPORT_KEY',
  github: {
    owner: 'octocat',
    repo: 'private-intake'
  },
  defaultLabels: ['team:solo'],
  allowedKinds: ['bug', 'feature', 'feedback'],
  maxPayloadSizeBytes: 4096,
  rateLimit: {
    mode: 'memory',
    windowSeconds: 60,
    maxRequests: 3
  },
  attachmentPolicy: {
    maxAttachmentBytes: 2048,
    maxAttachmentCount: 2,
    allowInlineData: true,
    allowRemoteUrls: true
  },
  dedupe: {
    mode: 'memory',
    windowSeconds: 3600
  }
};

describe('redactReportSecrets', () => {
  it('redacts common secret formats from notes, diagnostics, and screen context', () => {
    const report: ReportPayload = {
      appId: 'justcards',
      kind: 'bug',
      severity: 'high',
      notes: [
        'Authorization: Bearer TEST_APP_REPORT_KEY',
        'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456',
        'github_pat_ABCDEFGHIJKLMNOPQRSTUVWXYZ_1234567890',
        'sk-abcdefghijklmnopqrstuvwxyz123456',
        'password=supersecret',
        'api_key=abcdef123456',
        'token=secret-token',
        '-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----'
      ].join('\n'),
      email: 'user@example.com',
      metadata: {
        appVersion: '1.2.3',
        build: '42',
        osName: 'iOS',
        osVersion: '18.5',
        deviceModel: 'iPhone16,2',
        locale: 'en-AU',
        clientVersion: '0.1.0',
        screen: 'Authorization: Bearer TEST_APP_REPORT_KEY'
      },
      diagnostics: {
        header: 'Authorization: Bearer TEST_APP_REPORT_KEY',
        githubToken: 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456',
        githubPat: 'github_pat_ABCDEFGHIJKLMNOPQRSTUVWXYZ_1234567890',
        apiKey: 'sk-abcdefghijklmnopqrstuvwxyz123456',
        password: 'password=supersecret',
        genericToken: 'token=secret-token'
      },
      attachments: [
        {
          filename: 'screenshot.png',
          contentType: 'image/png',
          byteCount: 128,
          url: 'https://cdn.example.com/report.png?token=secret-query',
          sha256: 'deadbeef'
        }
      ]
    };

    const sanitized = redactReportSecrets(report);
    const issueBody = renderIssueBody({
      appConfig,
      report: sanitized,
      fingerprint: 'fingerprint-123',
      submittedAt: new Date('2026-05-30T00:00:00.000Z'),
      enrichment: null
    });

    expect(issueBody).not.toContain('Authorization: Bearer');
    expect(issueBody).not.toContain('TEST_APP_REPORT_KEY');
    expect(issueBody).not.toContain('ghp_');
    expect(issueBody).not.toContain('github_pat_');
    expect(issueBody).not.toContain('sk-abcdefghijklmnopqrstuvwxyz123456');
    expect(issueBody).not.toContain('password=supersecret');
    expect(issueBody).not.toContain('api_key=abcdef123456');
    expect(issueBody).not.toContain('token=secret-token');
    expect(issueBody).not.toContain('BEGIN RSA PRIVATE KEY');
    expect(issueBody).toContain('[REDACTED_SECRET]');
    expect(issueBody).toContain('[REDACTED_PRIVATE_KEY]');
    expect(issueBody).not.toContain('?token=');
  });
});
