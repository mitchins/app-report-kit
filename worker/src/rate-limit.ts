import { SafeHttpError } from './errors';

import type {
  Env,
  RateLimitBinding,
  RateLimitPolicy,
  RateLimitResult,
  RateLimiter
} from './types';

export class MemoryRateLimiter implements RateLimiter {
  private readonly requests = new Map<string, number[]>();

  constructor(private readonly nowMs: () => number = () => Date.now()) {}

  async check(key: string, policy: RateLimitPolicy): Promise<RateLimitResult> {
    const now = this.nowMs();
    const windowStart = now - policy.windowSeconds * 1_000;
    const timestamps = (this.requests.get(key) ?? []).filter((timestamp) => timestamp >= windowStart);

    if (timestamps.length >= policy.maxRequests) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((timestamps[0] + policy.windowSeconds * 1_000 - now) / 1_000)
      );
      this.requests.set(key, timestamps);
      return { allowed: false, retryAfterSeconds };
    }

    timestamps.push(now);
    this.requests.set(key, timestamps);
    return { allowed: true };
  }
}

function isRateLimitBinding(value: unknown): value is RateLimitBinding {
  return typeof value === 'object' && value !== null && typeof (value as RateLimitBinding).limit === 'function';
}

export class ConfiguredRateLimiter implements RateLimiter {
  constructor(
    private readonly env: Env,
    private readonly memoryRateLimiter: MemoryRateLimiter = new MemoryRateLimiter()
  ) {}

  async check(key: string, policy: RateLimitPolicy): Promise<RateLimitResult> {
    if (policy.mode === 'memory') {
      return this.memoryRateLimiter.check(key, policy);
    }

    const binding = this.env[policy.bindingName];
    if (!isRateLimitBinding(binding)) {
      throw new SafeHttpError(503, 'Request could not be accepted.', 'failed_rate_limit_unavailable');
    }

    const result = await binding.limit({ key });
    if (typeof result.allowed === 'boolean') {
      return {
        allowed: result.allowed,
        retryAfterSeconds: result.retryAfterSeconds
      };
    }
    if (typeof result.success === 'boolean') {
      return {
        allowed: result.success,
        retryAfterSeconds: result.retryAfterSeconds
      };
    }

    throw new SafeHttpError(503, 'Request could not be accepted.', 'failed_rate_limit_unavailable');
  }
}
