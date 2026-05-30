import { z } from 'zod';

const nonEmptyTrimmedString = z.string().trim().min(1);

export const reportPayloadSchema = z.object({
  appId: nonEmptyTrimmedString,
  kind: z.enum(['bug', 'feature', 'feedback']),
  severity: z.enum(['low', 'normal', 'high']).default('normal'),
  notes: z.string().trim().min(1, 'notes are required'),
  email: z
    .string()
    .trim()
    .email()
    .optional(),
  metadata: z.object({
    appVersion: nonEmptyTrimmedString,
    build: nonEmptyTrimmedString,
    osName: nonEmptyTrimmedString,
    osVersion: nonEmptyTrimmedString,
    deviceModel: nonEmptyTrimmedString,
    locale: nonEmptyTrimmedString,
    clientVersion: nonEmptyTrimmedString,
    screen: nonEmptyTrimmedString.optional()
  }),
  diagnostics: z.record(z.string(), z.string()).optional(),
  attachments: z
    .array(
      z
        .object({
          filename: nonEmptyTrimmedString,
          contentType: nonEmptyTrimmedString,
          byteCount: z.number().int().nonnegative().optional(),
          dataBase64: z.string().min(1).optional(),
          url: z.string().url().optional(),
          sha256: nonEmptyTrimmedString.optional()
        })
        .refine(
          (attachment) =>
            attachment.dataBase64 !== undefined ||
            attachment.url !== undefined ||
            attachment.sha256 !== undefined,
          'attachment must include dataBase64, url, or sha256'
        )
    )
    .default([])
}).strict();

export type ParsedReportPayload = z.infer<typeof reportPayloadSchema>;
