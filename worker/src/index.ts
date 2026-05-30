import { ConfiguredDuplicateStore, MemoryDuplicateStore } from './dedupe-store';
import { FetchGitHubIssueClient } from './github';
import { handleRequest } from './handler';
import { ConfiguredRateLimiter, MemoryRateLimiter } from './rate-limit';

import type { Env, ReportEnrichmentProvider } from './types';

const duplicateStore = new MemoryDuplicateStore();
const rateLimiter = new MemoryRateLimiter();
const enrichmentProvider: ReportEnrichmentProvider = {
  async enrich() {
    return null;
  }
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const githubClient = new FetchGitHubIssueClient(String(env.GITHUB_TOKEN ?? ''));
    return handleRequest(request, env, {
      githubClient,
      rateLimiter: new ConfiguredRateLimiter(env, rateLimiter),
      duplicateStore: new ConfiguredDuplicateStore(env, duplicateStore),
      enrichmentProvider,
      now: () => new Date()
    });
  }
};
