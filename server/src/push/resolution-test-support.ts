// Test support for resolution fan-out tests: APNs env, seeded audience, captured pushes.
// Exports helpers only used by *.test.ts files; uses real WebCrypto and the cloudflare:test D1.
// All tokens, handles and keys here are fake fixtures.
import { env } from 'cloudflare:test';
import { vi } from 'vitest';
import type { Env } from '../types';

export const RELAY_PUSH_KEY = 'b'.repeat(42) + 'A';

export async function apnsEnv(): Promise<Env> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey) as ArrayBuffer);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
  return { ...env, APNS_KEY_ID: 'KEY1234567', APNS_TEAM_ID: 'TEAM123456', APNS_AUTH_KEY: pem };
}

/** A fake relay handle unique to the test prefix (relay handles are unique per device). */
export function relayHandle(prefix: string): string {
  return (prefix.replace(/[^A-Za-z0-9_-]/g, '') + 'a'.repeat(43)).slice(0, 43);
}

export interface SeededAudience { agentId: string; bossId: string }

/** An agent, a manager boss with access to it, and an optional push device for that boss. */
export async function seedAudience(prefix: string, device?: { token: string; relay?: boolean },
  preferences: string | null = null): Promise<SeededAudience> {
  const agentId = `${prefix}-agent`;
  const bossId = `${prefix}-boss`;
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, `${prefix} agent`, `${prefix}-hash`),
    env.DB.prepare(`INSERT INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET preferences = excluded.preferences`)
      .bind(bossId, `${prefix} boss`, 'manager', preferences),
    env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(bossId, agentId),
  ]);
  if (device) {
    const handle = relayHandle(prefix);
    await env.DB.prepare(`INSERT INTO boss_devices (boss_id, device_token, bundle_id, environment, platform,
      relay_handle, push_key) VALUES (?, ?, 'ai.hiboss.app', 'sandbox', 'ios', ?, ?)`)
      .bind(bossId, device.relay ? `relay:${handle}` : device.token,
        device.relay ? handle : null, device.relay ? RELAY_PUSH_KEY : null).run();
  }
  return { agentId, bossId };
}

export async function insertAsk(id: string, agentId: string, fields: Record<string, unknown> = {}): Promise<void> {
  const row: Record<string, unknown> = { id, agent_id: agentId, direction: 'agent_to_boss', mode: 'async',
    channel: 'api', body: 'Ship it?', status: 'sent', priority: 'normal',
    metadata: JSON.stringify({ options: ['Ship', 'Hold'] }), ...fields };
  const columns = Object.keys(row);
  await env.DB.prepare(`INSERT INTO messages (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`)
    .bind(...columns.map((column) => row[column] ?? null)).run();
}

export interface CapturedRequest { url: string; headers: Record<string, string>; body: Record<string, unknown> }

/** Stubs fetch; every request is recorded and answered with `status`. */
export function captureFetch(status = 200): CapturedRequest[] {
  const captured: CapturedRequest[] = [];
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const text = typeof init?.body === 'string' ? init.body : '{}';
    let body: Record<string, unknown> = {};
    try { body = JSON.parse(text) as Record<string, unknown>; } catch { body = {}; }
    captured.push({ url: String(input), headers: (init?.headers ?? {}) as Record<string, string>, body });
    return new Response(status === 200 ? '{}' : JSON.stringify({ reason: 'Unregistered' }), { status });
  }));
  return captured;
}

function decode(value: string): Uint8Array<ArrayBuffer> {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, '=')), c => c.charCodeAt(0));
}

/** Decrypts a relay `resolved` ciphertext with the fixture push key and the `resolved` AAD. */
export async function openResolved(ciphertext: string): Promise<Record<string, unknown>> {
  const bytes = decode(ciphertext);
  const key = await crypto.subtle.importKey('raw', decode(RELAY_PUSH_KEY), 'AES-GCM', false, ['decrypt']);
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12),
    additionalData: new TextEncoder().encode('hiboss-push-v1|resolved') }, key, bytes.slice(12));
  return JSON.parse(new TextDecoder().decode(plain)) as Record<string, unknown>;
}

/** Message ids announced to the relay with kind `resolved`, paired with their status. */
export async function relayResolutions(captured: CapturedRequest[]): Promise<Record<string, unknown>[]> {
  const sent = captured.filter((r) => r.url.endsWith('/v1/push') && r.body.kind === 'resolved');
  return Promise.all(sent.map((r) => openResolved(String(r.body.ciphertext))));
}
