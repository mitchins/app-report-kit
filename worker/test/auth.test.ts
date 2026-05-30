import { describe, expect, it } from 'vitest';

import { SafeHttpError } from '../src/errors';
import { extractBearerToken, getExpectedBearerKey, isAuthorized } from '../src/auth';

import type { AppConfig, Env } from '../src/types';

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

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    JUSTCARDS_PROD_REPORT_KEY: 'TEST_APP_REPORT_KEY',
    ...overrides
  } as Env;
}

describe('auth helpers', () => {
  it('extracts bearer tokens only from valid authorization headers', () => {
    expect(extractBearerToken(new Request('https://example.com'))).toBeNull();
    expect(
      extractBearerToken(
        new Request('https://example.com', {
          headers: { authorization: 'Bearer TEST_TOKEN' }
        })
      )
    ).toBe('TEST_TOKEN');
    expect(
      extractBearerToken(
        new Request('https://example.com', {
          headers: { authorization: 'Basic TEST_TOKEN' }
        })
      )
    ).toBeNull();
    expect(
      extractBearerToken(
        new Request('https://example.com', {
          headers: { authorization: 'Bearer TEST_TOKEN extra' }
        })
      )
    ).toBeNull();
  });

  it('reads the configured bearer key from env and rejects missing values', () => {
    expect(getExpectedBearerKey(makeEnv(), appConfig)).toBe('TEST_APP_REPORT_KEY');

    expect(() =>
      getExpectedBearerKey(makeEnv({ JUSTCARDS_PROD_REPORT_KEY: '' }), appConfig)
    ).toThrow(SafeHttpError);
  });

  it('compares bearer tokens safely across matching and mismatching values', () => {
    expect(isAuthorized('TEST_APP_REPORT_KEY', 'TEST_APP_REPORT_KEY')).toBe(true);
    expect(isAuthorized('WRONG_KEY', 'TEST_APP_REPORT_KEY')).toBe(false);
    expect(isAuthorized(null, 'TEST_APP_REPORT_KEY')).toBe(false);
    expect(isAuthorized('TEST_APP_REPORT_KEY extra', 'TEST_APP_REPORT_KEY')).toBe(false);
    expect(isAuthorized('🔒_TOKEN', '🔒_TOKEN')).toBe(true);
    expect(isAuthorized('🔑_TOKEN', '🔒_TOKEN')).toBe(false);
  });
});
