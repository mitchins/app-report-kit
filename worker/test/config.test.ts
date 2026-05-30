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
  function expectConfigFailure(input: unknown): SafeHttpError {
    try {
      loadConfig(makeEnv(input));
      throw new Error('Expected config loading to fail.');
    } catch (error) {
      expect(error).toBeInstanceOf(SafeHttpError);
      const safeError = error as SafeHttpError;
      expect(safeError.status).toBe(500);
      expect(safeError.category).toBe('failed_config');
      return safeError;
    }
  }

  it('rejects literal bearer token values in config by requiring binding-style names', () => {
    expectConfigFailure({
      runtimeMode: 'local',
      apps: [
        {
          appId: 'justcards',
          bearerKeyBinding: [['g', 'h', 'p'].join(''), '_literal_token_value'].join(''),
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
    });
  });

  it('rejects extra token fields in app config', () => {
    expectConfigFailure({
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
    });
  });

  it('rejects production config that still uses memory rate limiting or dedupe', () => {
    expectConfigFailure({
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
    });
  });

  it('rejects duplicate app ids in config', () => {
    expectConfigFailure({
      runtimeMode: 'local',
      apps: [
        {
          appId: 'justcards',
          bearerKeyBinding: 'JUSTCARDS_ONE_REPORT_KEY',
          github: {
            owner: 'octocat',
            repo: 'private-intake'
          },
          defaultLabels: [],
          allowedKinds: ['bug'],
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
        },
        {
          appId: 'justcards',
          bearerKeyBinding: 'JUSTCARDS_TWO_REPORT_KEY',
          github: {
            owner: 'octocat',
            repo: 'private-intake'
          },
          defaultLabels: [],
          allowedKinds: ['bug'],
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
    });
  });
});
