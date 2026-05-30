import { SafeHttpError } from './errors';
import { extractBearerToken, getExpectedBearerKey, isAuthorized } from './auth';
import { buildFingerprint, hashClientIp } from './fingerprint';
import { buildIssueLabels, buildIssueTitle, renderIssueBody } from './issue-renderer';
import { loadConfig } from './config';
import { acceptedResponse, failureResponse } from './response';
import { redactReportSecrets } from './redaction';
import { reportPayloadSchema } from './schema';

import type {
  AppConfig,
  Env,
  FeedbackAttachment,
  RequestHandlingResult,
  RequestResultCategory,
  ReportPayload,
  WorkerDependencies
} from './types';

const ABSOLUTE_MAX_REQUEST_BYTES = 256 * 1024;

function requireRoute(request: Request): void {
  const url = new URL(request.url);
  if (url.pathname !== '/v1/report') {
    throw new SafeHttpError(404, 'Request could not be accepted.', 'route_not_found');
  }
  if (request.method.toUpperCase() !== 'POST') {
    throw new SafeHttpError(405, 'Request could not be accepted.', 'method_not_allowed');
  }
}

function parseJsonBody(rawBody: string): unknown {
  try {
    return JSON.parse(rawBody);
  } catch {
    throw new SafeHttpError(400, 'Request could not be accepted.', 'rejected_invalid_request');
  }
}

function requireAppConfig(body: unknown, env: Env): AppConfig {
  const appId = typeof body === 'object' && body !== null ? Reflect.get(body, 'appId') : undefined;
  const config = loadConfig(env).apps.get(typeof appId === 'string' ? appId.trim() : '');
  if (!config) {
    throw new SafeHttpError(401, 'Request could not be accepted.', 'rejected_unknown_app');
  }
  return config;
}

function validateAttachmentPolicy(report: ReportPayload, appConfig: AppConfig): void {
  if (report.attachments.length > appConfig.attachmentPolicy.maxAttachmentCount) {
    throw new SafeHttpError(413, 'Request could not be accepted.', 'rejected_oversized_attachment');
  }

  for (const attachment of report.attachments) {
    validateAttachment(attachment, appConfig);
  }
}

function validateAttachment(attachment: FeedbackAttachment, appConfig: AppConfig): void {
  if (attachment.dataBase64 && !appConfig.attachmentPolicy.allowInlineData) {
    throw new SafeHttpError(413, 'Request could not be accepted.', 'rejected_oversized_attachment');
  }

  if (attachment.url && !appConfig.attachmentPolicy.allowRemoteUrls) {
    throw new SafeHttpError(413, 'Request could not be accepted.', 'rejected_oversized_attachment');
  }

  const inferredByteCount =
    attachment.byteCount ??
    (attachment.dataBase64 ? Math.ceil((attachment.dataBase64.length * 3) / 4) : 0);

  if (inferredByteCount > appConfig.attachmentPolicy.maxAttachmentBytes) {
    throw new SafeHttpError(413, 'Request could not be accepted.', 'rejected_oversized_attachment');
  }

  if (!attachment.url && !attachment.dataBase64 && !attachment.sha256) {
    throw new SafeHttpError(400, 'Request could not be accepted.', 'rejected_invalid_request');
  }
}

function categorizeSchemaFailure(body: unknown): RequestResultCategory {
  const parsed = reportPayloadSchema.safeParse(body);
  if (parsed.success) {
    return 'rejected_invalid_request';
  }

  for (const issue of parsed.error.issues) {
    const path = issue.path.join('.');
    if (path === 'notes') {
      return 'rejected_missing_notes';
    }
    if (path === 'kind') {
      return 'rejected_invalid_kind';
    }
  }

  return 'rejected_invalid_request';
}

function parseAndValidateReport(body: unknown, appConfig: AppConfig): ReportPayload {
  const parsed = reportPayloadSchema.safeParse(body);
  if (!parsed.success) {
    throw new SafeHttpError(
      400,
      'Request could not be accepted.',
      categorizeSchemaFailure(body)
    );
  }

  if (!appConfig.allowedKinds.includes(parsed.data.kind)) {
    throw new SafeHttpError(400, 'Request could not be accepted.', 'rejected_invalid_kind');
  }

  const report = redactReportSecrets(parsed.data);
  validateAttachmentPolicy(report, appConfig);
  return report;
}

export async function processRequest(
  request: Request,
  env: Env,
  dependencies: WorkerDependencies
): Promise<RequestHandlingResult> {
  let githubAttempted = false;
  let issueCreated = false;

  try {
    requireRoute(request);

    const token = extractBearerToken(request);
    if (!token) {
      throw new SafeHttpError(401, 'Request could not be accepted.', 'rejected_missing_auth');
    }

    const rawBodyBuffer = await request.arrayBuffer();
    const bodyByteLength = rawBodyBuffer.byteLength;
    if (bodyByteLength > ABSOLUTE_MAX_REQUEST_BYTES) {
      throw new SafeHttpError(413, 'Request could not be accepted.', 'rejected_oversized_payload');
    }
    const rawBody = new TextDecoder().decode(rawBodyBuffer);

    const parsedBody = parseJsonBody(rawBody);
    const appConfig = requireAppConfig(parsedBody, env);
    const expectedBearerKey = getExpectedBearerKey(env, appConfig);
    if (!isAuthorized(token, expectedBearerKey)) {
      throw new SafeHttpError(401, 'Request could not be accepted.', 'rejected_invalid_auth');
    }

    if (bodyByteLength > appConfig.maxPayloadSizeBytes) {
      throw new SafeHttpError(413, 'Request could not be accepted.', 'rejected_oversized_payload');
    }

    const report = parseAndValidateReport(parsedBody, appConfig);
    const ipHash = await hashClientIp(request);
    const rateLimitResult = await dependencies.rateLimiter.check(
      `${appConfig.bearerKeyBinding}:${ipHash}`,
      appConfig.rateLimit
    );
    if (!rateLimitResult.allowed) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil(rateLimitResult.retryAfterSeconds ?? appConfig.rateLimit.windowSeconds)
      );
      throw new SafeHttpError(429, 'Request could not be accepted.', 'rejected_rate_limited', {
        'retry-after': String(retryAfterSeconds)
      });
    }

    const fingerprint = await buildFingerprint(report);
    const duplicateKey = `${report.appId}:${fingerprint}`;
    const existingDuplicate = await dependencies.duplicateStore.findRecent(
      duplicateKey,
      appConfig.dedupe
    );

    if (existingDuplicate) {
      return {
        response: acceptedResponse(),
        category: 'accepted_duplicate',
        githubAttempted: false,
        issueCreated: false
      };
    }

    const submittedAt = dependencies.now();
    const enrichment = await dependencies.enrichmentProvider.enrich(report);
    const issueRequest = {
      owner: appConfig.github.owner,
      repo: appConfig.github.repo,
      title: buildIssueTitle(report),
      body: renderIssueBody({
        appConfig,
        report,
        fingerprint,
        submittedAt,
        enrichment
      }),
      labels: buildIssueLabels(appConfig, report)
    };

    githubAttempted = true;
    try {
      const createdIssue = await dependencies.githubClient.createIssue(issueRequest);
      issueCreated = true;

      try {
        await dependencies.duplicateStore.record(
          duplicateKey,
          {
            fingerprint,
            issueNumber: createdIssue.issueNumber,
            recordedAt: submittedAt.toISOString()
          },
          appConfig.dedupe
        );
      } catch {
        return {
          response: acceptedResponse(),
          category: 'accepted_without_dedupe_record',
          githubAttempted: true,
          issueCreated: true
        };
      }

      return {
        response: acceptedResponse(),
        category: 'accepted',
        githubAttempted: true,
        issueCreated: true
      };
    } catch (error) {
      if (error instanceof SafeHttpError) {
        throw error;
      }
      return {
        response: failureResponse(502),
        category: 'failed_github',
        githubAttempted,
        issueCreated
      };
    }
  } catch (error) {
    if (error instanceof SafeHttpError) {
      return {
        response: failureResponse(error.status, error.headers),
        category: error.category,
        githubAttempted,
        issueCreated
      };
    }
    return {
      response: failureResponse(500),
      category: 'failed_internal',
      githubAttempted,
      issueCreated
    };
  }
}

export async function handleRequest(
  request: Request,
  env: Env,
  dependencies: WorkerDependencies
): Promise<Response> {
  const result = await processRequest(request, env, dependencies);
  return result.response;
}
