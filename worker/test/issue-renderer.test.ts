import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { buildIssueLabels, buildIssueTitle, renderIssueBody } from '../src/issue-renderer';

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

const report: ReportPayload = {
  appId: 'justcards',
  kind: 'bug',
  severity: 'high',
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
    lastAction: 'Tapped Export'
  },
  attachments: [
    {
      filename: 'screenshot.png',
      contentType: 'image/png',
      byteCount: 128,
      url: 'https://user:pass@cdn.example.com/reports/screenshot.png?token=secret',
      sha256: 'deadbeef'
    }
  ]
};

describe('issue renderer', () => {
  it('renders a stable issue title, labels, and body fixture', () => {
    const title = buildIssueTitle(report);
    const labels = buildIssueLabels(appConfig, report);
    const body = renderIssueBody({
      appConfig,
      report,
      fingerprint: 'test-fingerprint-123',
      submittedAt: new Date('2026-05-30T00:00:00.000Z'),
      enrichment: {
        buildChannel: 'production'
      }
    });
    const expectedBody = readFileSync(
      new URL('./fixtures/expected-issue-body.md', import.meta.url),
      'utf8'
    );

    expect(title).toBe('[justcards][Bug] Export fails from invoice editor');
    expect(labels).toEqual([
      'team:solo',
      'source:in-app',
      'app:justcards',
      'kind:bug',
      'severity:high',
      'platform:ios'
    ]);
    expect(body).toBe(expectedBody.trimEnd());
  });
});
