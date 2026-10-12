// Compact JWS (ES256) verification shared by boss and agent message signing.
// Exports verifyCompactJws, peekJwsKeyId, decodeJsonSegment and isFresh.
// Depends on base64url and ES256 helpers in crypto.

import { decodeBase64Url, verifyEs256 } from './crypto';

export const MAX_CLOCK_SKEW_SECONDS = 300;

export interface JwsKey {
  readonly keyId: string;
  readonly publicKey: string;
}

/** Returns the verified payload, or null for any malformed, mismatched or invalid token. */
export async function verifyCompactJws(
  compact: string,
  key: JwsKey,
  type: string,
): Promise<Record<string, unknown> | null> {
  const segments = compact.split('.');
  if (segments.length !== 3) return null;
  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  if (!encodedHeader || !encodedPayload || !encodedSignature) return null;
  const header = decodeJsonSegment(encodedHeader);
  const payload = decodeJsonSegment(encodedPayload);
  const signature = decodeBase64Url(encodedSignature);
  const publicKey = decodeBase64Url(key.publicKey);
  if (!header || !payload || !signature || !publicKey) return null;
  if (header['alg'] !== 'ES256' || header['kid'] !== key.keyId || header['typ'] !== type) return null;
  const signingInput = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);
  return await verifyEs256(publicKey, signature, signingInput) ? payload : null;
}

/** Reads the unverified `kid` so the caller can select the key that must verify the token. */
export function peekJwsKeyId(compact: string): string | null {
  const encodedHeader = compact.split('.')[0];
  if (!encodedHeader) return null;
  const kid = decodeJsonSegment(encodedHeader)?.['kid'];
  return typeof kid === 'string' && kid ? kid : null;
}

export function decodeJsonSegment(value: string): Record<string, unknown> | null {
  const bytes = decodeBase64Url(value);
  if (!bytes) return null;
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

export function isFresh(issuedAt: number): boolean {
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - issuedAt) <= MAX_CLOCK_SKEW_SECONDS;
}
