// Shared typed validation results and protocol error codes.
// Exports ValidationResult, ValidationIssue, and failure helpers.
// Dependencies: none.

export type ValidationCode =
  | 'invalid_spec'
  | 'invalid_answers'
  | 'unsupported_catalog';

export interface ValidationIssue {
  readonly code: ValidationCode;
  readonly path: string;
  readonly message: string;
  readonly keyword?: string;
}

export type ValidationResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: ValidationIssue };

export function failure(
  code: ValidationCode,
  path: string,
  message: string,
  keyword?: string,
): ValidationResult<never> {
  return {
    ok: false,
    error: keyword === undefined ? { code, path, message } : { code, path, message, keyword },
  };
}
