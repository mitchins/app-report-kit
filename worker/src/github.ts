import type { GitHubIssueClient, GitHubIssueResult, IssueCreationRequest } from './types';

interface GitHubIssueResponse {
  number: number;
  html_url: string;
}

const GITHUB_TIMEOUT_MS = 10_000;

export class FetchGitHubIssueClient implements GitHubIssueClient {
  constructor(
    private readonly token: string,
    private readonly fetchImpl: typeof fetch = fetch
  ) {}

  async createIssue(request: IssueCreationRequest): Promise<GitHubIssueResult> {
    const abortController = new AbortController();
    const timeoutId = setTimeout(() => abortController.abort(), GITHUB_TIMEOUT_MS);

    const response = await this.fetchImpl(
      `https://api.github.com/repos/${request.owner}/${request.repo}/issues`,
      {
        method: 'POST',
        signal: abortController.signal,
        headers: {
          authorization: `Bearer ${this.token}`,
          accept: 'application/vnd.github+json',
          'content-type': 'application/json',
          'user-agent': 'AppReportKit-Worker'
        },
        body: JSON.stringify({
          title: request.title,
          body: request.body,
          labels: request.labels
        })
      }
    ).finally(() => clearTimeout(timeoutId));

    if (!response.ok) {
      throw new Error(`GitHub issue creation failed with status ${response.status}`);
    }

    const data = (await response.json()) as GitHubIssueResponse;
    return {
      issueNumber: data.number,
      htmlUrl: data.html_url
    };
  }
}
