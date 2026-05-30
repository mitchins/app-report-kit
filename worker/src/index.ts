import { ConfiguredDuplicateStore, MemoryDuplicateStore } from './dedupe-store';
import { SafeHttpError } from './errors';
import { FetchGitHubIssueClient } from './github';
import { handleRequest } from './handler';
import { ConfiguredRateLimiter, MemoryRateLimiter } from './rate-limit';
import { failureResponse } from './response';

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
    try {
      if (typeof env.GITHUB_TOKEN !== 'string' || env.GITHUB_TOKEN.length === 0) {
        throw new SafeHttpError(500, 'Request could not be accepted.', 'failed_config');
      }

      const githubClient = new FetchGitHubIssueClient(env.GITHUB_TOKEN);
      return handleRequest(request, env, {
        githubClient,
        rateLimiter: new ConfiguredRateLimiter(env, rateLimiter),
        duplicateStore: new ConfiguredDuplicateStore(env, duplicateStore),
        enrichmentProvider,
        now: () => new Date()
      });
    } catch (error) {
      if (error instanceof SafeHttpError) {
        return failureResponse(error.status, error.headers);
      }
      return failureResponse(500);
    }
  }
};
