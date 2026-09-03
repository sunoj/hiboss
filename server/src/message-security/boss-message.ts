// Authenticates optional signed boss replies and rejects key-bound downgrades.
// Exports authenticateBossReply with authoritative body and provenance metadata.
// Depends on D1, JWS helpers, and server-owned provenance builders.

import type { Env } from '../types';
import { decodeBase64Url, verifyEs256 } from './crypto';
import { bearerApiMetadata, signedApiMetadata } from './provenance';
import type {
  BossMessageAuthResult,
  SignedBossPayload,
  StoredSigningKey,
} from './types';

const MAX_CLOCK_SKEW_SECONDS = 300;
const MESSAGE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f-]{27,}$/i;

interface ReplyAuthenticationInput {
  readonly env: Env;
  readonly bossId: string;
  readonly bossName: string;
  readonly tokenId: string;
  readonly parentMessageId: string;
  readonly body: string;
  readonly signedMessage?: unknown;
}

export async function authenticateBossReply(
  input: ReplyAuthenticationInput,
): Promise<BossMessageAuthResult> {
  const key = await findSigningKey(input.env, input.tokenId);
  if (!key) return authenticateBearerReply(input);
  if (key.boss_id !== input.bossId) return failure(401, 'signing key identity mismatch');
  if (typeof input.signedMessage !== 'string' || !input.signedMessage) {
    return failure(401, 'signed message required');
  }
  const verified = await verifySignedReply(input.signedMessage, key);
  if (!verified) return failure(401, 'invalid signed message');
  if (!matchesRequest(verified.payload, input)) {
    return failure(401, 'signed message does not match request');
  }
  if (!isFresh(verified.payload.issued_at)) return failure(401, 'stale signed message');
  return {
    ok: true,
    value: {
      body: verified.payload.body,
      idempotencyKey: `sig:${key.id}:${verified.payload.message_id}`,
      provenance: signedApiMetadata(
        { id: input.bossId, name: input.bossName }, input.tokenId, key, input.signedMessage,
      ),
    },
  };
}

function authenticateBearerReply(input: ReplyAuthenticationInput): BossMessageAuthResult {
  if (input.signedMessage !== undefined) {
    return failure(400, 'signing key not registered');
  }
  return {
    ok: true,
    value: {
      body: input.body,
      idempotencyKey: null,
      provenance: bearerApiMetadata(
        { id: input.bossId, name: input.bossName }, input.tokenId,
      ),
    },
  };
}

async function findSigningKey(env: Env, tokenId: string): Promise<StoredSigningKey | null> {
  return env.DB.prepare(
    `SELECT id, boss_id, boss_token_id, algorithm, client_kind, public_key
     FROM boss_signing_keys WHERE boss_token_id = ? AND revoked_at IS NULL`,
  ).bind(tokenId).first<StoredSigningKey>();
}

async function verifySignedReply(
  compact: string,
  key: StoredSigningKey,
): Promise<{ payload: SignedBossPayload } | null> {
  const segments = compact.split('.');
  if (segments.length !== 3) return null;
  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  if (!encodedHeader || !encodedPayload || !encodedSignature) return null;
  const header = decodeJson(encodedHeader);
  const payload = decodeJson(encodedPayload);
  const signature = decodeBase64Url(encodedSignature);
  const publicKey = decodeBase64Url(key.public_key);
  if (!header || !payload || !signature || !publicKey) return null;
  if (header['alg'] !== 'ES256' || header['kid'] !== key.id) return null;
  if (header['typ'] !== 'hiboss-message+jws') return null;
  const signingInput = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);
  if (!(await verifyEs256(publicKey, signature, signingInput))) return null;
  return isSignedBossPayload(payload) ? { payload } : null;
}

function decodeJson(value: string): Record<string, unknown> | null {
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

function isSignedBossPayload(
  value: Record<string, unknown>,
): value is Record<string, unknown> & SignedBossPayload {
  const action = value['action'];
  if (!action || typeof action !== 'object' || Array.isArray(action)) return false;
  const actionRecord = action as Record<string, unknown>;
  return value['version'] === 1
    && value['purpose'] === 'hiboss.boss-message'
    && typeof value['message_id'] === 'string'
    && MESSAGE_ID_PATTERN.test(value['message_id'])
    && Number.isInteger(value['issued_at'])
    && typeof value['boss_id'] === 'string'
    && typeof value['body'] === 'string'
    && actionRecord['kind'] === 'reply'
    && typeof actionRecord['message_id'] === 'string';
}

function matchesRequest(payload: SignedBossPayload, input: ReplyAuthenticationInput): boolean {
  return payload.boss_id === input.bossId
    && payload.action.message_id === input.parentMessageId
    && payload.body === input.body;
}

function isFresh(issuedAt: number): boolean {
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - issuedAt) <= MAX_CLOCK_SKEW_SECONDS;
}

function failure(status: 400 | 401, error: string): BossMessageAuthResult {
  return { ok: false, status, error };
}
