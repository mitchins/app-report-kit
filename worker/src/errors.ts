import type { RequestResultCategory } from './types';

export class SafeHttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly messageBody = 'Request could not be accepted.',
    public readonly category: RequestResultCategory = 'failed_internal'
  ) {
    super(messageBody);
  }
}
