import { z } from 'zod';

import { SafeHttpError } from './errors';

import type { Env, LoadedConfig, WorkerConfig } from './types';

const secretBindingNameSchema = z.string().regex(/^[A-Z][A-Z0-9_]{1,127}$/);
const configCache = new WeakMap<Env, LoadedConfig>();

const appConfigSchema = z.object({
  appId: z.string().min(1),
  bearerKeyBinding: secretBindingNameSchema,
  github: z
    .object({
      owner: z.string().min(1),
      repo: z.string().min(1)
    })
    .strict(),
  defaultLabels: z.array(z.string().min(1)).default([]),
  allowedKinds: z.array(z.enum(['bug', 'feature', 'feedback'])).min(1),
  maxPayloadSizeBytes: z.number().int().positive(),
  rateLimit: z.discriminatedUnion('mode', [
    z
      .object({
        mode: z.literal('memory'),
        windowSeconds: z.number().int().positive(),
        maxRequests: z.number().int().positive()
      })
      .strict(),
    z
      .object({
        mode: z.literal('binding'),
        windowSeconds: z.number().int().positive(),
        maxRequests: z.number().int().positive(),
        bindingName: secretBindingNameSchema
      })
      .strict()
  ]),
  attachmentPolicy: z
    .object({
      maxAttachmentBytes: z.number().int().nonnegative(),
      maxAttachmentCount: z.number().int().nonnegative(),
      allowInlineData: z.boolean(),
      allowRemoteUrls: z.boolean()
    })
    .strict(),
  dedupe: z.discriminatedUnion('mode', [
    z
      .object({
        mode: z.literal('memory'),
        windowSeconds: z.number().int().positive()
      })
      .strict(),
    z
      .object({
        mode: z.literal('kv'),
        windowSeconds: z.number().int().positive(),
        bindingName: secretBindingNameSchema
      })
      .strict()
  ])
}).strict();

const workerConfigSchema = z
  .object({
    runtimeMode: z.enum(['local', 'production']),
    apps: z.array(appConfigSchema)
  })
  .strict();

function assertProductionBindings(config: WorkerConfig): void {
  if (config.runtimeMode !== 'production') {
    return;
  }

  for (const app of config.apps) {
    if (app.rateLimit.mode === 'memory' || app.dedupe.mode === 'memory') {
      throw new SafeHttpError(500, 'Request could not be accepted.', 'failed_config');
    }
  }
}

export function loadConfig(env: Env): LoadedConfig {
  const cached = configCache.get(env);
  if (cached) {
    return cached;
  }

  try {
    if (typeof env.APP_CONFIG_JSON !== 'string' || env.APP_CONFIG_JSON.trim().length === 0) {
      throw new SafeHttpError(500, 'Request could not be accepted.', 'failed_config');
    }

    const parsed = workerConfigSchema.parse(JSON.parse(env.APP_CONFIG_JSON));
    assertProductionBindings(parsed);
    const appIds = new Set<string>();
    for (const app of parsed.apps) {
      if (appIds.has(app.appId)) {
        throw new SafeHttpError(500, 'Request could not be accepted.', 'failed_config');
      }
      appIds.add(app.appId);
    }

    const loaded: LoadedConfig = {
      runtimeMode: parsed.runtimeMode,
      apps: new Map(parsed.apps.map((app) => [app.appId, app]))
    };
    configCache.set(env, loaded);

    return loaded;
  } catch (error) {
    if (error instanceof SafeHttpError) {
      throw error;
    }
    throw new SafeHttpError(500, 'Request could not be accepted.', 'failed_config');
  }
}
