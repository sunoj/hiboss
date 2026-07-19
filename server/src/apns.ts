// APNs HTTP/2-over-fetch sender for Cloudflare Workers.
// Exports config detection, payload/result types, and sendPush.
// Depends on Workers WebCrypto, fetch, and APNs env secrets.

import type { Env } from './types';

export type ApnsEnvironment = 'sandbox' | 'production';
export type ApnsInterruptionLevel = 'active' | 'time-sensitive' | 'critical';

export interface ApnsPayload {
  aps: {
    alert: { title: string; body: string };
    sound: 'default';
    'interruption-level': ApnsInterruptionLevel;
    'thread-id': string;
  };
  [key: string]: unknown;
}

export type ApnsSendResult =
  | { ok: true; prune: false }
  | { ok: false; prune: boolean; reason: string };

interface JwtCache {
  token: string;
  expiresAt: number;
  keyId: string;
  teamId: string;
  authKey: string;
}

let jwtCache: JwtCache | null = null;
const JWT_TTL_MS = 50 * 60 * 1000;

export function hasApnsConfig(env: Env): boolean {
  return !!(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_AUTH_KEY);
}

export async function sendPush(
  env: Env,
  deviceToken: string,
  environment: ApnsEnvironment,
  bundleId: string,
  payload: ApnsPayload,
): Promise<ApnsSendResult> {
  const keyId = env.APNS_KEY_ID;
  const teamId = env.APNS_TEAM_ID;
  const authKey = env.APNS_AUTH_KEY;
  if (!keyId || !teamId || !authKey) {
    return { ok: false, prune: false, reason: 'missing APNs config' };
  }
  const jwt = await getProviderJwt(keyId, teamId, authKey);
  const host = environment === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'content-type': 'application/json',
      'apns-topic': bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) {
    return { ok: true, prune: false };
  }
  const reason = await parseApnsReason(response);
  const prune = response.status === 410 || reason === 'BadDeviceToken';
  return { ok: false, prune, reason: reason ?? `APNs ${response.status}` };
}

async function getProviderJwt(keyId: string, teamId: string, authKey: string): Promise<string> {
  const now = Date.now();
  if (
    jwtCache &&
    jwtCache.expiresAt > now &&
    jwtCache.keyId === keyId &&
    jwtCache.teamId === teamId &&
    jwtCache.authKey === authKey
  ) {
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
  jwtCache = { token, expiresAt: now + JWT_TTL_MS, keyId, teamId, authKey };
  return token;
}

async function parseApnsReason(response: Response): Promise<string | null> {
  try {
    const body = await response.json() as unknown;
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

function base64UrlBytes(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
