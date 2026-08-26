export default class DubbingError extends Error {
  constructor(code, message, options = {}) {
    super(message, options.cause ? { cause: options.cause } : undefined);
    this.name = 'DubbingError';
    this.code = code;
    this.retryable = Boolean(options.retryable);
  }
}

export function toDubbingError(error, fallbackCode = 'DUBBING_FAILED') {
  if (error instanceof DubbingError) return error;
  return new DubbingError(fallbackCode, error?.message || 'Dubbing failed', {
    cause: error,
  });
}
