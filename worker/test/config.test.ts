import { describe, expect, it } from 'vitest';

import { SafeHttpError } from '../src/errors';
import { loadConfig } from '../src/config';

import type { Env } from '../src/types';

function makeEnv(appConfig: unknown): Env {
  return {
    APP_CONFIG_JSON: JSON.stringify(appConfig),
    GITHUB_TOKEN: 'TEST_GITHUB_TOKEN'
  };
}

describe('loadConfig', () => {
  it('rejects literal bearer token values in config by requiring binding-style names', () => {
    expect(() =>
      loadConfig(
        makeEnv({
          runtimeMode: 'local',
          apps: [
            {
              appId: 'justcards',
              bearerKeyBinding: 'ghp_literal_token_value',
              github: {
                owner: 'octocat',
                repo: 'private-intake'
              },
              defaultLabels: [],
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
            }
          ]
        })
      )
    ).toThrowError(SafeHttpError);
  });

  it('rejects extra token fields in app config', () => {
    expect(() =>
      loadConfig(
        makeEnv({
          runtimeMode: 'local',
          apps: [
            {
              appId: 'justcards',
              bearerKeyBinding: 'JUSTCARDS_PROD_REPORT_KEY',
              bearerToken: 'should-not-be-here',
              github: {
                owner: 'octocat',
                repo: 'private-intake'
              },
              defaultLabels: [],
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
            }
          ]
        })
      )
    ).toThrowError(SafeHttpError);
  });

  it('rejects production config that still uses memory rate limiting or dedupe', () => {
    expect(() =>
      loadConfig(
        makeEnv({
          runtimeMode: 'production',
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
            }
          ]
        })
      )
    ).toThrowError(SafeHttpError);
  });
});
