import { SafeHttpError } from './errors';

import type { AppConfig, Env } from './types';

export function extractBearerToken(request: Request): string | null {
  const header = request.headers.get('authorization');
  if (!header) {
    return null;
  }

  const [scheme, token] = header.split(/\s+/, 2);
  if (scheme?.toLowerCase() !== 'bearer' || !token) {
    return null;
  }

  return token;
}

export function getExpectedBearerKey(env: Env, appConfig: AppConfig): string {
  const expected = env[appConfig.bearerKeyBinding];
  if (typeof expected !== 'string' || expected.length === 0) {
    throw new SafeHttpError(500, 'Request could not be accepted.', 'failed_config');
  }

  return expected;
}

export function isAuthorized(token: string | null, expected: string): boolean {
  if (!token) {
    return false;
  }

  return token === expected;
}
