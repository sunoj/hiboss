// Strict request body parsing for the relay API.
// Bodies are size-capped before and while reading; every parser rejects unknown fields,
// wrong types and out-of-range values with null.

import type { ApnsEnvironment, ApnsPriority, InterruptionLevel, PushBody, PushKind, TokenBody } from './types';

export const MAX_BODY_CHARS = 8192;
export const MAX_CIPHERTEXT_BYTES = 2048;
/** nonce(12) + AES-GCM tag(16): anything shorter cannot be a valid ciphertext. */
export const MIN_CIPHERTEXT_BYTES = 28;

const KINDS: readonly PushKind[] = ['decision', 'message', 'system'];
const PRIORITIES: readonly ApnsPriority[] = [5, 10];
const INTERRUPTIONS: readonly InterruptionLevel[] = ['passive', 'active', 'time-sensitive'];
const ENVIRONMENTS: readonly ApnsEnvironment[] = ['sandbox', 'production'];
const APNS_TOKEN = /^[0-9a-fA-F]{64,200}$/;
const COLLAPSE_ID = /^[A-Za-z0-9_-]{1,64}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;

type JsonObject = Record<string, unknown>;

/** True when `Content-Length` is present and at most MAX_BODY_CHARS; checked before reading. */
export function declaredSizeOk(request: Request): boolean {
  const declared = request.headers.get('Content-Length');
  return declared !== null && /^\d{1,5}$/.test(declared) && Number(declared) <= MAX_BODY_CHARS;
}

/** Reads a body of at most MAX_BODY_CHARS bytes, enforcing the limit while reading. */
export async function readLimitedBody(request: Request): Promise<string | null> {
  if (!declaredSizeOk(request)) return null;
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BODY_CHARS) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

export function parseJsonObject(text: string | null): JsonObject | null {
  if (text === null || text.length > MAX_BODY_CHARS) return null;
  try {
    const value: unknown = JSON.parse(text);
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
    return value as JsonObject;
  } catch {
    return null;
  }
}

function hasOnlyKeys(obj: JsonObject, allowed: readonly string[]): boolean {
  return Object.keys(obj).every((key) => allowed.includes(key));
}

function isOneOf<T extends string>(value: unknown, options: readonly T[]): value is T {
  return typeof value === 'string' && (options as readonly string[]).includes(value);
}

export function parseTokenBody(obj: JsonObject): TokenBody | null {
  if (!hasOnlyKeys(obj, ['apnsToken', 'environment'])) return null;
  const { apnsToken, environment } = obj;
  if (typeof apnsToken !== 'string' || !APNS_TOKEN.test(apnsToken)) return null;
  if (!isOneOf(environment, ENVIRONMENTS)) return null;
  return { apnsToken: apnsToken.toLowerCase(), environment };
}

/** Decoded byte length of unpadded base64url, or null when the text is not base64url. */
export function base64UrlDecodedLength(text: string): number | null {
  if (!BASE64URL.test(text) || text.length % 4 === 1) return null;
  return Math.floor((text.length * 3) / 4);
}

const PUSH_KEYS = ['handle', 'kind', 'ciphertext', 'collapseId', 'priority', 'interruption', 'sound'];

export function parsePushBody(obj: JsonObject): PushBody | null {
  if (!hasOnlyKeys(obj, PUSH_KEYS)) return null;
  const { handle, kind, ciphertext, collapseId, priority, interruption, sound } = obj;
  if (typeof handle !== 'string' || !isOneOf(kind, KINDS)) return null;
  if (!PRIORITIES.some((p) => p === priority) || !isOneOf(interruption, INTERRUPTIONS)) return null;
  if (typeof sound !== 'boolean') return null;
  if (typeof ciphertext !== 'string') return null;
  const size = base64UrlDecodedLength(ciphertext);
  if (size === null || size < MIN_CIPHERTEXT_BYTES || size > MAX_CIPHERTEXT_BYTES) return null;
  const body: PushBody = { handle, kind, ciphertext, priority: priority as ApnsPriority, interruption, sound };
  if (collapseId === undefined) return body;
  if (typeof collapseId !== 'string' || !COLLAPSE_ID.test(collapseId)) return null;
  return { ...body, collapseId };
}
