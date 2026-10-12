// Test-only agent signer: P-256 keys, enrollment proofs, endorsements and message JWS.
// Exports TestAgent helpers used by agent signing E2E tests.
// Depends on Web Crypto, cloudflare:test D1 and the auth hash helper.

import { env, SELF } from 'cloudflare:test';
import { hashApiKey } from '../middleware/auth';

export const base = 'https://test.local/api';
const encoder = new TextEncoder();

export interface TestAgent { id: string; token: string; keyId: string }
export interface TestSigner { privateKey: CryptoKey; publicKey: string; keyId: string }

export function request(path: string, token: string, method = 'GET', body?: unknown): Promise<Response> {
  return SELF.fetch(base + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

export async function seedAgent(name: string): Promise<TestAgent> {
  const token = `hb_${name}`;
  const hash = await hashApiKey(token);
  const row = await env.DB.prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id')
    .bind(name, hash).first<{ id: string }>();
  if (!row) throw new Error('seed failed');
  const keyId = crypto.randomUUID();
  await env.DB.prepare("INSERT INTO agent_keys (id, agent_id, key_hash, label) VALUES (?, ?, ?, 'test')")
    .bind(keyId, row.id, hash).run();
  return { id: row.id, token, keyId };
}

export function b64url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

export async function newSigner(): Promise<TestSigner> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const raw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey) as ArrayBuffer);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', raw));
  return { privateKey: pair.privateKey, publicKey: b64url(raw), keyId: b64url(digest) };
}

async function sign(signer: TestSigner, input: string): Promise<string> {
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, signer.privateKey, encoder.encode(input));
  return b64url(new Uint8Array(signature));
}

export async function jws(signer: TestSigner, typ: string, payload: Record<string, unknown>): Promise<string> {
  const header = b64url(encoder.encode(JSON.stringify({ alg: 'ES256', kid: signer.keyId, typ })));
  const body = b64url(encoder.encode(JSON.stringify(payload)));
  return `${header}.${body}.${await sign(signer, `${header}.${body}`)}`;
}

export async function enrollment(agent: TestAgent, signer: TestSigner, endorser?: TestSigner): Promise<Record<string, unknown>> {
  const proof = await sign(signer, `hiboss-agent-key-v1\n${agent.keyId}\n${agent.id}\n${signer.publicKey}`);
  const endorsement = endorser ? await jws(endorser, 'hiboss-agent-key+jws', {
    version: 1, purpose: 'hiboss.agent-key-endorsement', agent_id: agent.id,
    agent_key_id: agent.keyId, key_id: signer.keyId, issued_at: now(),
  }) : undefined;
  return { public_key: signer.publicKey, proof, endorsement };
}

export function now(): number {
  return Math.floor(Date.now() / 1000);
}

/** A signed message payload with send defaults; `overrides` replaces any field. */
export function messagePayload(agentId: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    version: 1, purpose: 'hiboss.agent-message', message_id: crypto.randomUUID(), issued_at: now(),
    agent_id: agentId, session_id: null, action: { kind: 'send', audience: { kind: 'boss' } },
    body: 'Deploy finished', mode: 'async', timeout: null, file_url: null, options: null, metadata: null,
    ...overrides,
  };
}

export async function signedMessage(signer: TestSigner, payload: Record<string, unknown>): Promise<string> {
  return jws(signer, 'hiboss-agent-message+jws', payload);
}
