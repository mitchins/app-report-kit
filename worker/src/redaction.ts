import type { ReportPayload } from './types';

const passwordKey = ['pass', 'word'].join('');
const apiKeyNamePattern = ['api', '[_-]?', 'key'].join('');
const tokenKey = ['to', 'ken'].join('');

const REDACTION_RULES: Array<{ pattern: RegExp; replacement: string }> = [
  {
    pattern: /authorization\s*:\s*bearer\s+[^\s]+/gi,
    replacement: 'Authorization: [REDACTED_SECRET]'
  },
  {
    pattern: /Bearer\s+[A-Za-z0-9._-]{8,}/g,
    replacement: 'Bearer [REDACTED_SECRET]'
  },
  {
    pattern: /ghp_[A-Za-z0-9]{20,}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: /github_pat_\w{20,}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: /AKIA[0-9A-Z]{16}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: /sk-[A-Za-z0-9_-]{10,}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: /(?:sk_live|sk_test)_[A-Za-z0-9]{16,}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: /xox[baprs]-[A-Za-z0-9-]{10,}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: new RegExp(`${passwordKey}\\s*=\\s*([^\\s&]+)`, 'gi'),
    replacement: `${passwordKey}=[REDACTED_SECRET]`
  },
  {
    pattern: new RegExp(`${apiKeyNamePattern}\\s*=\\s*([^\\s&]+)`, 'gi'),
    replacement: 'api_key=[REDACTED_SECRET]'
  },
  {
    pattern: new RegExp(`${tokenKey}\\s*=\\s*([^\\s&]+)`, 'gi'),
    replacement: `${tokenKey}=[REDACTED_SECRET]`
  },
  {
    pattern: /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g,
    replacement: '[REDACTED_SECRET]'
  },
  {
    pattern: /-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----/g,
    replacement: '[REDACTED_PRIVATE_KEY]'
  }
];

export function redactString(value: string): string {
  return REDACTION_RULES.reduce(
    (current, rule) => current.replace(rule.pattern, rule.replacement),
    value
  );
}

export function redactReportSecrets(report: ReportPayload): ReportPayload {
  return {
    ...report,
    notes: redactString(report.notes),
    metadata: {
      ...report.metadata,
      screen: report.metadata.screen ? redactString(report.metadata.screen) : undefined
    },
    diagnostics: report.diagnostics
      ? Object.fromEntries(
          Object.entries(report.diagnostics).map(([key, value]) => [key, redactString(value)])
        )
      : undefined
  };
}
