// Decodes stored JSON with the existing null fallback for absent or malformed input.
// Exports parseStoredJSON; it preserves parsed values and leaves shape validation to callers.
// Dependencies: the Metadata contract and built-in JSON parsing.

import type { Metadata } from './types';

export function parseStoredJSON(value: string | null | undefined): Metadata {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as Metadata;
  } catch {
    return null;
  }
}
