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

const sampleAppReportKey = 'TEST_APP_REPORT_KEY';
const samplePat = [['g', 'h', 'p'].join(''), '_', 'A'.repeat(32)].join('');
const sampleFineGrainedPat = [['github', 'pat'].join('_'), '_', 'A'.repeat(26), '_', '1234567890'].join('');
const sampleProviderKey = [['s', 'k'].join(''), '-', 'a'.repeat(26)].join('');
const samplePasswordAssignment = [['pass', 'word'].join(''), '=', 'demo-value'].join('');
const sampleApiKeyAssignment = [['api', 'key'].join('_'), '=', 'abcdef123456'].join('');
const sampleTokenAssignment = [['to', 'ken'].join(''), '=', 'demo-token'].join('');
const samplePrivateKeyBlock = [
  '-----BEGIN RSA PRIVATE ',
  'KEY-----\nabc\n-----END RSA PRIVATE ',
  'KEY-----'
].join('');
const authHeaderPrefix = ['Authorization', ': ', 'Bearer '].join('');
const patPrefix = ['g', 'h', 'p', '_'].join('');
const fineGrainedPatPrefix = ['github', 'pat'].join('_') + '_';
const providerKeyPrefix = ['s', 'k'].join('') + '-';
const privateKeyPrefix = ['BEGIN RSA PRIVATE ', 'KEY'].join('');

describe('redactReportSecrets', () => {
  it('redacts common secret formats from notes, diagnostics, and screen context', () => {
    const report: ReportPayload = {
      appId: 'justcards',
      kind: 'bug',
      severity: 'high',
      notes: [
        `${authHeaderPrefix}${sampleAppReportKey}`,
        samplePat,
        sampleFineGrainedPat,
        sampleProviderKey,
        samplePasswordAssignment,
        sampleApiKeyAssignment,
        sampleTokenAssignment,
        samplePrivateKeyBlock
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
        screen: `${authHeaderPrefix}${sampleAppReportKey}`
      },
      diagnostics: {
        header: `${authHeaderPrefix}${sampleAppReportKey}`,
        accessCredential: samplePat,
        fineGrainedCredential: sampleFineGrainedPat,
        providerCredential: sampleProviderKey,
        passwordEntry: samplePasswordAssignment,
        tokenEntry: sampleTokenAssignment
      },
      attachments: [
        {
          filename: 'screenshot.png',
          contentType: 'image/png',
          byteCount: 128,
          url: 'https://user:pass@cdn.example.com/report.png?token=secret-query',
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
      enrichment: {
        injectedHeader: `${authHeaderPrefix}${sampleAppReportKey}`
      }
    });

    expect(issueBody).not.toContain(authHeaderPrefix);
    expect(issueBody).not.toContain(sampleAppReportKey);
    expect(issueBody).not.toContain(patPrefix);
    expect(issueBody).not.toContain(fineGrainedPatPrefix);
    expect(issueBody).not.toContain(providerKeyPrefix);
    expect(issueBody).not.toContain(samplePasswordAssignment);
    expect(issueBody).not.toContain(sampleApiKeyAssignment);
    expect(issueBody).not.toContain(sampleTokenAssignment);
    expect(issueBody).not.toContain(privateKeyPrefix);
    expect(issueBody).toContain('[REDACTED_SECRET]');
    expect(issueBody).toContain('[REDACTED_PRIVATE_KEY]');
    expect(issueBody).not.toContain('user:pass@');
    expect(issueBody).not.toContain('?token=');
  });
});
