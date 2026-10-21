// APNs sender for the relay: provider JWT (ES256) plus one alert push per call.
// The alert is generic and chosen by kind only; the ciphertext rides in custom key `e`.
// Depends on Workers WebCrypto, fetch and the APNS_* Worker secrets.

import { base64UrlBytes } from './crypto';
import type { ApnsEnvironment, Env, PushKind } from './types';

export const BUNDLE_ID = 'ai.hiboss.app';
export const TITLE_LOC_KEY = 'HIBOSS_PUSH_TITLE';
const BODY_LOC_KEYS: Record<PushKind, string> = {
  decision: 'HIBOSS_PUSH_DECISION',
  message: 'HIBOSS_PUSH_MESSAGE',
  system: 'HIBOSS_PUSH_SYSTEM',
};

export type ApnsOutcome = 'sent' | 'gone' | 'failed' | 'unconfigured';

export interface RelayPush {
  apnsToken: string;
  environment: ApnsEnvironment;
  kind: PushKind;
  ciphertext: string;
  collapseId?: string;
}

interface JwtCache {
  token: string;
  expiresAt: number;
  cacheKey: string;
}

let jwtCache: JwtCache | null = null;
const JWT_TTL_MS = 50 * 60 * 1000;

export function buildPayload(push: RelayPush): Record<string, unknown> {
  const aps: Record<string, unknown> = {
    alert: { 'title-loc-key': TITLE_LOC_KEY, 'loc-key': BODY_LOC_KEYS[push.kind] },
    sound: 'default',
    'mutable-content': 1,
  };
  if (push.collapseId) aps['thread-id'] = push.collapseId;
  return { aps, e: push.ciphertext };
}

export async function sendApns(env: Env, push: RelayPush): Promise<ApnsOutcome> {
  const { APNS_KEY_ID: keyId, APNS_TEAM_ID: teamId, APNS_AUTH_KEY: authKey } = env;
  if (!keyId || !teamId || !authKey) return 'unconfigured';
  const jwt = await providerJwt(keyId, teamId, authKey);
  const host = push.environment === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    'content-type': 'application/json',
    'apns-topic': BUNDLE_ID,
    'apns-push-type': 'alert',
    'apns-priority': push.kind === 'decision' ? '10' : '5',
  };
  if (push.collapseId) headers['apns-collapse-id'] = push.collapseId;
  const response = await fetch(`https://${host}/3/device/${push.apnsToken}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(buildPayload(push)),
  });
  if (response.ok) return 'sent';
  if (response.status === 410) return 'gone';
  return (await apnsReason(response)) === 'BadDeviceToken' ? 'gone' : 'failed';
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
