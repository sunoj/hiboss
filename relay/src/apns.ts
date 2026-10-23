// APNs sender for the relay: provider JWT (ES256), one push per call, and the background push
// that proves APNs accepts a token before it is stored. An alert is generic and chosen by kind
// only; `resolved` is a background push. The ciphertext rides in custom key `e`. An alert's
// priority, interruption level and sound come verbatim from the Server's delivery level.
// Depends on Workers WebCrypto, fetch and the APNS_* Worker secrets.

import { base64UrlBytes } from './crypto';
import type { AlertKind, AlertPush, ApnsEnvironment, Env, ResolvedPush, TokenBody } from './types';

export const BUNDLE_ID = 'ai.hiboss.app';
export const TITLE_LOC_KEY = 'HIBOSS_PUSH_TITLE';
const BODY_LOC_KEYS: Record<AlertKind, string> = {
  decision: 'HIBOSS_PUSH_DECISION',
  message: 'HIBOSS_PUSH_MESSAGE',
  system: 'HIBOSS_PUSH_SYSTEM',
};

export type ApnsOutcome = 'sent' | 'gone' | 'failed' | 'unconfigured';
export type TokenCheck = 'valid' | 'invalid' | 'failed' | 'unconfigured';

export const VERIFY_TIMEOUT_MS = 5_000;
const BACKGROUND_PAYLOAD = JSON.stringify({ aps: { 'content-available': 1 } });
const BACKGROUND_HEADERS = { 'apns-push-type': 'background', 'apns-priority': '5' };

export type RelayPush = (AlertPush | ResolvedPush) & {
  apnsToken: string;
  environment: ApnsEnvironment;
};

interface JwtCache {
  token: string;
  expiresAt: number;
  cacheKey: string;
}

let jwtCache: JwtCache | null = null;
const JWT_TTL_MS = 50 * 60 * 1000;

export function buildPayload(push: RelayPush): Record<string, unknown> {
  if (push.kind === 'resolved') return { aps: { 'content-available': 1 }, e: push.ciphertext };
  const aps: Record<string, unknown> = {
    alert: { 'title-loc-key': TITLE_LOC_KEY, 'loc-key': BODY_LOC_KEYS[push.kind] },
    'interruption-level': push.interruption,
    'mutable-content': 1,
  };
  if (push.sound) aps.sound = 'default';
  if (push.collapseId) aps['thread-id'] = push.collapseId;
  return { aps, e: push.ciphertext };
}

export async function sendApns(env: Env, push: RelayPush): Promise<ApnsOutcome> {
  const headers: Record<string, string> = {
    'apns-push-type': push.kind === 'resolved' ? 'background' : 'alert',
    'apns-priority': String(push.priority),
  };
  if (push.kind !== 'resolved' && push.collapseId) headers['apns-collapse-id'] = push.collapseId;
  const response = await postApns(env, push, headers, JSON.stringify(buildPayload(push)));
  if (!response) return 'unconfigured';
  if (response.ok) return 'sent';
  if (response.status === 410) return 'gone';
  return (await apnsReason(response)) === 'BadDeviceToken' ? 'gone' : 'failed';
}

/**
 * Sends one background push to the token in its environment. 200 → valid; APNs rejecting the
 * token (400 or 410) → invalid; any other status, a transport error or the timeout → failed.
 */
export async function verifyToken(env: Env, token: TokenBody): Promise<TokenCheck> {
  let response: Response | null;
  try {
    const signal = AbortSignal.timeout(VERIFY_TIMEOUT_MS);
    response = await postApns(env, token, BACKGROUND_HEADERS, BACKGROUND_PAYLOAD, signal);
  } catch {
    return 'failed';
  }
  if (!response) return 'unconfigured';
  if (response.ok) return 'valid';
  return response.status === 400 || response.status === 410 ? 'invalid' : 'failed';
}

/** One APNs request for `ai.hiboss.app`; null when the APNs secrets are not configured. */
async function postApns(
  env: Env,
  target: TokenBody,
  headers: Record<string, string>,
  body: string,
  signal?: AbortSignal,
): Promise<Response | null> {
  const { APNS_KEY_ID: keyId, APNS_TEAM_ID: teamId, APNS_AUTH_KEY: authKey } = env;
  if (!keyId || !teamId || !authKey) return null;
  const jwt = await providerJwt(keyId, teamId, authKey);
  const host = target.environment === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  return await fetch(`https://${host}/3/device/${target.apnsToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'content-type': 'application/json',
      'apns-topic': BUNDLE_ID,
      ...headers,
    },
    body,
    signal,
  });
}

async function providerJwt(keyId: string, teamId: string, authKey: string): Promise<string> {
  const now = Date.now();
  const cacheKey = `${keyId}|${teamId}|${authKey}`;
  if (jwtCache && jwtCache.expiresAt > now && jwtCache.cacheKey === cacheKey) {
    return jwtCache.token;
  }
  const header = base64UrlJson({ alg: 'ES256', kid: keyId });
  const claims = base64UrlJson({ iss: teamId, iat: Math.floor(now / 1000) });
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(authKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  );
  const token = `${signingInput}.${base64UrlBytes(new Uint8Array(signature))}`;
  jwtCache = { token, expiresAt: now + JWT_TTL_MS, cacheKey };
  return token;
}

async function apnsReason(response: Response): Promise<string | null> {
  try {
    const body: unknown = await response.json();
    if (body && typeof body === 'object' && 'reason' in body) {
      const reason = (body as { reason?: unknown }).reason;
      return typeof reason === 'string' ? reason : null;
    }
  } catch {
    return null;
  }
  return null;
}

function base64UrlJson(value: Record<string, string | number>): string {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
