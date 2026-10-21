// Shared relay test helpers: request builder, APNs fetch mock, fake rate limiters, fixtures, DB reset.
// Calls the Worker entry directly so the stubbed global fetch is the APNs boundary.

import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test';
import { vi } from 'vitest';
import worker from '../src/index';
import type { Env } from '../src/types';

export const TOKEN_A = 'a'.repeat(64);
export const TOKEN_B = 'b'.repeat(64);
export const CIPHERTEXT = 'A'.repeat(40);
export const DELIVERY = { priority: 10, interruption: 'active', sound: true } as const;
export const FIXED_NOW = Date.UTC(2026, 9, 21, 10, 0, 0);

let apnsKeyPem: string | null = null;

async function testAuthKey(): Promise<string> {
  if (apnsKeyPem) return apnsKeyPem;
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey('pkcs8', pair.privateKey)) as ArrayBuffer);
  const base64 = btoa(String.fromCharCode(...pkcs8));
  apnsKeyPem = `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`;
  return apnsKeyPem;
}

export interface FakeLimiter extends RateLimit {
  keys: string[];
}

/** A Rate Limiting binding stand-in that records keys and allows or refuses every call. */
export function fakeLimiter(allow = true): FakeLimiter {
  const keys: string[] = [];
  return {
    keys,
    async limit({ key }) {
      keys.push(key);
      return { success: allow };
    },
  };
}

export async function relayEnv(overrides: Partial<Env> = {}): Promise<Env> {
  return {
    DB: env.DB,
    PUSH_RATE_LIMITER: fakeLimiter(),
    REGISTRATION_RATE_LIMITER: fakeLimiter(),
    APNS_KEY_ID: 'KEYID12345',
    APNS_TEAM_ID: 'TEAM123456',
    APNS_AUTH_KEY: await testAuthKey(),
    ...overrides,
  };
}

export interface CallOptions {
  body?: unknown;
  raw?: string;
  ip?: string;
  secret?: string;
  env?: Env;
  url?: string;
  headers?: Record<string, string>;
  /** Overrides the computed Content-Length; null omits the header. */
  contentLength?: string | null;
}

export async function call(method: string, path: string, opts: CallOptions = {}): Promise<Response> {
  const headers: Record<string, string> = { 'CF-Connecting-IP': opts.ip ?? '203.0.113.1' };
  if (opts.secret !== undefined) headers.Authorization = `Bearer ${opts.secret}`;
  const body = opts.raw ?? (opts.body === undefined ? undefined : JSON.stringify(opts.body));
  if (body !== undefined) headers['content-type'] = 'application/json';
  const computed = body === undefined ? null : String(new TextEncoder().encode(body).byteLength);
  const length = opts.contentLength === undefined ? computed : opts.contentLength;
  if (length !== null) headers['Content-Length'] = length;
  Object.assign(headers, opts.headers);
  const request = new Request(`${opts.url ?? 'https://push.test'}${path}`, { method, headers, body });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, opts.env ?? (await relayEnv()), ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

export function mockApns(status = 200, reason?: string) {
  const fetchMock = vi.fn<typeof fetch>(async () =>
    reason ? Response.json({ reason }, { status }) : new Response(null, { status }),
  );
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

export async function register(
  token = TOKEN_A,
  environment = 'production',
  ip?: string,
): Promise<{ handle: string; deviceSecret: string }> {
  const response = await call('POST', '/v1/registrations', { body: { apnsToken: token, environment }, ip });
  if (response.status !== 201) throw new Error(`register failed: ${response.status}`);
  return response.json();
}

export function pushBody(handle: string, extra: Record<string, unknown> = {}) {
  return { handle, kind: 'message', ciphertext: CIPHERTEXT, ...DELIVERY, ...extra };
}

export async function resetDb(): Promise<void> {
  await env.DB.batch([env.DB.prepare('DELETE FROM registrations'), env.DB.prepare('DELETE FROM rate_counters')]);
}

export async function countRows(table: 'registrations' | 'rate_counters'): Promise<number> {
  const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first<{ n: number }>();
  return row?.n ?? 0;
}
