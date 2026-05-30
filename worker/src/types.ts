export type ReportKind = 'bug' | 'feature' | 'feedback';
export type FeedbackSeverity = 'low' | 'normal' | 'high';
export type WorkerRuntimeMode = 'local' | 'production';
export type RequestResultCategory =
  | 'accepted'
  | 'accepted_duplicate'
  | 'accepted_without_dedupe_record'
  | 'route_not_found'
  | 'method_not_allowed'
  | 'rejected_missing_auth'
  | 'rejected_invalid_auth'
  | 'rejected_unknown_app'
  | 'rejected_invalid_request'
  | 'rejected_missing_notes'
  | 'rejected_invalid_kind'
  | 'rejected_oversized_payload'
  | 'rejected_oversized_attachment'
  | 'rejected_rate_limited'
  | 'failed_rate_limit_unavailable'
  | 'failed_dedupe_unavailable'
  | 'failed_config'
  | 'failed_github'
  | 'failed_internal';

export interface FeedbackAttachment {
  filename: string;
  contentType: string;
  byteCount?: number;
  dataBase64?: string;
  url?: string;
  sha256?: string;
}

export interface FeedbackMetadata {
  appVersion: string;
  build: string;
  osName: string;
  osVersion: string;
  deviceModel: string;
  locale: string;
  clientVersion: string;
  screen?: string;
}

export interface ReportPayload {
  appId: string;
  kind: ReportKind;
  severity: FeedbackSeverity;
  notes: string;
  email?: string;
  metadata: FeedbackMetadata;
  diagnostics?: Record<string, string>;
  attachments: FeedbackAttachment[];
}

export interface MemoryRateLimitPolicy {
  windowSeconds: number;
  maxRequests: number;
  mode: 'memory';
}

export interface BindingRateLimitPolicy {
  windowSeconds: number;
  maxRequests: number;
  mode: 'binding';
  bindingName: string;
}

export type RateLimitPolicy = MemoryRateLimitPolicy | BindingRateLimitPolicy;

export interface AttachmentPolicy {
  maxAttachmentBytes: number;
  maxAttachmentCount: number;
  allowInlineData: boolean;
  allowRemoteUrls: boolean;
}

export interface MemoryDedupePolicy {
  windowSeconds: number;
  mode: 'memory';
}

export interface KVDedupePolicy {
  windowSeconds: number;
  mode: 'kv';
  bindingName: string;
}

export type DedupePolicy = MemoryDedupePolicy | KVDedupePolicy;

export interface GitHubRepoTarget {
  owner: string;
  repo: string;
}

export interface AppConfig {
  appId: string;
  bearerKeyBinding: string;
  github: GitHubRepoTarget;
  defaultLabels: string[];
  allowedKinds: ReportKind[];
  maxPayloadSizeBytes: number;
  rateLimit: RateLimitPolicy;
  attachmentPolicy: AttachmentPolicy;
  dedupe: DedupePolicy;
}

export interface WorkerConfig {
  runtimeMode: WorkerRuntimeMode;
  apps: AppConfig[];
}

export interface LoadedConfig {
  runtimeMode: WorkerRuntimeMode;
  apps: Map<string, AppConfig>;
}

export interface Env {
  APP_CONFIG_JSON: string;
  GITHUB_TOKEN: string;
  [key: string]: unknown;
}

export interface IssueCreationRequest {
  owner: string;
  repo: string;
  title: string;
  body: string;
  labels: string[];
}

export interface GitHubIssueResult {
  issueNumber: number;
  htmlUrl: string;
}

export interface GitHubIssueClient {
  createIssue(request: IssueCreationRequest): Promise<GitHubIssueResult>;
}

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds?: number;
}

export interface RateLimiter {
  check(key: string, policy: RateLimitPolicy): Promise<RateLimitResult>;
}

export interface DuplicateRecord {
  fingerprint: string;
  issueNumber?: number;
  recordedAt: string;
}

export interface DuplicateStore {
  findRecent(key: string, policy: DedupePolicy): Promise<DuplicateRecord | null>;
  record(key: string, record: DuplicateRecord, policy: DedupePolicy): Promise<void>;
}

export interface ReportEnrichmentProvider {
  enrich(report: ReportPayload): Promise<Record<string, string> | null>;
}

export interface WorkerDependencies {
  githubClient: GitHubIssueClient;
  rateLimiter: RateLimiter;
  duplicateStore: DuplicateStore;
  enrichmentProvider: ReportEnrichmentProvider;
  now: () => Date;
}

export interface RequestHandlingResult {
  response: Response;
  category: RequestResultCategory;
  githubAttempted: boolean;
  issueCreated: boolean;
}

export interface RateLimitBinding {
  limit(input: { key: string }): Promise<
    | {
        success?: boolean;
        allowed?: boolean;
        retryAfterSeconds?: number;
      }
    | {
        success: boolean;
        allowed?: boolean;
        retryAfterSeconds?: number;
      }
  >;
}

export interface KVNamespaceLike {
  get(key: string): Promise<string | null>;
  put(
    key: string,
    value: string,
    options?: {
      expirationTtl?: number;
    }
  ): Promise<void>;
}
