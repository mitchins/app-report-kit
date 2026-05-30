import type { AppConfig, FeedbackAttachment, ReportPayload } from './types';

function toTitleCase(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function truncate(value: string, maxLength: number): string {
  return value.length <= maxLength ? value : `${value.slice(0, maxLength - 1)}…`;
}

function summaryFromNotes(notes: string): string {
  const firstLine = notes.split('\n').find((line) => line.trim().length > 0) ?? notes;
  return truncate(firstLine.trim().replace(/\s+/g, ' '), 80);
}

function escapeCell(value: string): string {
  return value.replace(/\|/g, '\\|').replace(/\n/g, '<br/>');
}

function renderTable(rows: Array<[string, string | undefined]>): string {
  const filtered = rows.filter(([, value]) => value && value.length > 0);
  if (filtered.length === 0) {
    return '_None_';
  }

  const lines = ['| Field | Value |', '| --- | --- |'];
  for (const [key, value] of filtered) {
    lines.push(`| ${escapeCell(key)} | ${escapeCell(value ?? '')} |`);
  }
  return lines.join('\n');
}

function normalizePlatform(osName: string): string {
  const normalized = osName.trim().toLowerCase();
  if (normalized === 'ios') {
    return 'ios';
  }
  if (normalized === 'macos') {
    return 'macos';
  }
  return 'unknown';
}

function renderAttachments(attachments: FeedbackAttachment[]): string {
  if (attachments.length === 0) {
    return '_None_';
  }

  const lines = [
    '| Filename | Content type | Size bytes | Reference | Digest |',
    '| --- | --- | --- | --- | --- |'
  ];

  for (const attachment of attachments) {
    const reference = attachment.url ? sanitizeAttachmentUrl(attachment.url) : 'inline payload omitted';
    lines.push(
      `| ${escapeCell(attachment.filename)} | ${escapeCell(attachment.contentType)} | ${attachment.byteCount?.toString() ?? 'unknown'} | ${escapeCell(reference)} | ${escapeCell(attachment.sha256 ?? 'n/a')} |`
    );
  }

  return lines.join('\n');
}

function sanitizeAttachmentUrl(url: string): string {
  try {
    const parsed = new URL(url);
    parsed.search = '';
    parsed.hash = '';
    return parsed.toString();
  } catch {
    return 'invalid-url';
  }
}

export function buildIssueTitle(report: ReportPayload): string {
  return `[${report.appId}][${toTitleCase(report.kind)}] ${summaryFromNotes(report.notes)}`;
}

export function buildIssueLabels(appConfig: AppConfig, report: ReportPayload): string[] {
  const labels = new Set([
    ...appConfig.defaultLabels,
    'source:in-app',
    `app:${report.appId}`,
    `kind:${report.kind}`,
    `severity:${report.severity}`,
    `platform:${normalizePlatform(report.metadata.osName)}`
  ]);
  return Array.from(labels);
}

export function renderIssueBody(input: {
  appConfig: AppConfig;
  report: ReportPayload;
  fingerprint: string;
  submittedAt: Date;
  enrichment?: Record<string, string> | null;
}): string {
  const { report, fingerprint, submittedAt, enrichment } = input;

  const sections = [
    '# In-app report',
    '',
    '## Summary',
    renderTable([
      ['Report type', report.kind],
      ['Severity', report.severity],
      ['User email', report.email],
      ['Submission timestamp', submittedAt.toISOString()],
      ['Content fingerprint', fingerprint]
    ]),
    '',
    '## Notes / Steps',
    report.notes,
    '',
    '## App metadata',
    renderTable([
      ['App ID', report.appId],
      ['App version', report.metadata.appVersion],
      ['Build', report.metadata.build],
      ['Client version', report.metadata.clientVersion],
      ['Screen/context', report.metadata.screen]
    ]),
    '',
    '## Device / software metadata',
    renderTable([
      ['OS name', report.metadata.osName],
      ['OS version', report.metadata.osVersion],
      ['Device model', report.metadata.deviceModel],
      ['Locale', report.metadata.locale]
    ]),
    '',
    '## Diagnostics / context',
    renderTable(
      Object.entries({
        ...(report.diagnostics ?? {}),
        ...(enrichment ?? {})
      })
    ),
    '',
    '## Attachments',
    renderAttachments(report.attachments)
  ];

  return sections.join('\n');
}

