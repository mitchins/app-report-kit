import { SafeHttpError } from './errors';

import type {
  DedupePolicy,
  DuplicateRecord,
  DuplicateStore,
  Env,
  KVNamespaceLike
} from './types';

interface StoredDuplicateRecord extends DuplicateRecord {
  recordedAtMs: number;
}

export class MemoryDuplicateStore implements DuplicateStore {
  private readonly records = new Map<string, StoredDuplicateRecord>();

  constructor(private readonly nowMs: () => number = () => Date.now()) {}

  async findRecent(key: string, policy: DedupePolicy): Promise<DuplicateRecord | null> {
    const existing = this.records.get(key);
    if (!existing) {
      return null;
    }

    if (this.nowMs() - existing.recordedAtMs > policy.windowSeconds * 1_000) {
      this.records.delete(key);
      return null;
    }

    return {
      fingerprint: existing.fingerprint,
      issueNumber: existing.issueNumber,
      recordedAt: existing.recordedAt
    };
  }

  async record(key: string, record: DuplicateRecord, _policy?: DedupePolicy): Promise<void> {
    this.records.set(key, {
      ...record,
      recordedAtMs: this.nowMs()
    });
  }
}

function isKVNamespaceLike(value: unknown): value is KVNamespaceLike {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as KVNamespaceLike).get === 'function' &&
    typeof (value as KVNamespaceLike).put === 'function'
  );
}

export class ConfiguredDuplicateStore implements DuplicateStore {
  constructor(
    private readonly env: Env,
    private readonly memoryStore: MemoryDuplicateStore = new MemoryDuplicateStore()
  ) {}

  async findRecent(key: string, policy: DedupePolicy): Promise<DuplicateRecord | null> {
    if (policy.mode === 'memory') {
      return this.memoryStore.findRecent(key, policy);
    }

    const binding = this.env[policy.bindingName];
    if (!isKVNamespaceLike(binding)) {
      throw new SafeHttpError(503, 'Request could not be accepted.', 'failed_dedupe_unavailable');
    }

    const value = await binding.get(key);
    if (!value) {
      return null;
    }

    try {
      return JSON.parse(value) as DuplicateRecord;
    } catch {
      throw new SafeHttpError(503, 'Request could not be accepted.', 'failed_dedupe_unavailable');
    }
  }

  async record(key: string, record: DuplicateRecord, policy: DedupePolicy): Promise<void> {
    if (policy.mode === 'memory') {
      return this.memoryStore.record(key, record, policy);
    }

    const binding = this.env[policy.bindingName];
    if (!isKVNamespaceLike(binding)) {
      throw new SafeHttpError(503, 'Request could not be accepted.', 'failed_dedupe_unavailable');
    }

    await binding.put(key, JSON.stringify(record), {
      expirationTtl: Math.max(policy.windowSeconds, 60)
    });
  }
}
