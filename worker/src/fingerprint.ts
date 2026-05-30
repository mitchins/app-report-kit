import type { ReportPayload } from './types';

function normalizeText(input: string, maxLength = 2_000): string {
  return input.trim().replace(/\s+/g, ' ').toLowerCase().slice(0, maxLength);
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

export function buildFingerprintSeed(report: ReportPayload): string {
  return [
    normalizeText(report.appId, 120),
    normalizeText(report.kind, 32),
    normalizeText(report.notes),
    normalizeText(report.metadata.appVersion, 64),
    normalizeText(report.metadata.osName, 64),
    normalizeText(report.metadata.osVersion, 64),
    normalizeText(report.metadata.deviceModel, 120)
  ].join('\n');
}

export async function buildFingerprint(report: ReportPayload): Promise<string> {
  return sha256Hex(buildFingerprintSeed(report));
}

export async function hashClientIp(request: Request): Promise<string> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  return sha256Hex(normalizeText(ip, 120));
}

