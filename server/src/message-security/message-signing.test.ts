// End-to-end contract for paired-device signatures and agent-visible provenance.
// Covers pairing key binding, downgrade rejection, tampering, and replay idempotency.
// Depends on the worker API, D1 test fixtures, and Web Crypto P-256 support.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const ROOT_TOKEN = 'hb_boss_signing_root_0011223344556677';
const PARENT_ID = 'signed-reply-parent';
const encoder = new TextEncoder();
let bossId: string;
let signedToken: string;
let signingKeyId: string;
let signingKey: CryptoKey;

beforeAll(async () => {
  await seedDatabase();
  bossId = await seedBossToken('Signing Boss', 'admin', ROOT_TOKEN, 'signing-boss');
  await env.DB.prepare(
    'INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)',
  ).bind(bossId, getTestAgentId()).run();
  await env.DB.prepare(
    "INSERT OR REPLACE INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')",
  ).bind(PARENT_ID, getTestAgentId(), 'Approve signed change?').run();

  const pair = await pairSigningClient();
  signedToken = pair.token;
  signingKeyId = pair.signingKeyId;
  signingKey = pair.privateKey;
});

describe('paired-device message signing', () => {
  it('binds the pairing token to the supplied P-256 public key', async () => {
    const row = await env.DB.prepare(
      'SELECT id, boss_id, algorithm, client_kind FROM boss_signing_keys WHERE id = ?',
    ).bind(signingKeyId).first<Record<string, unknown>>();
    expect(row).toEqual({
      id: signingKeyId,
      boss_id: bossId,
      algorithm: 'ES256',
      client_kind: 'ios',
    });
  });

  it('delivers a signed reply with independently verifiable provenance', async () => {
    const signedMessage = await signReply('Approve', crypto.randomUUID());
    const response = await reply({ body: 'Approve', source: 'discord', signed_message: signedMessage });
    expect(response.status).toBe(201);
    const message = await response.json() as SignedReplyResponse;
    expect(message.body).toBe('Approve');
    expect(message.metadata.source).toBe('ios');
    expect(message.metadata.provenance.source).toBe('ios');
    expect(message.metadata.provenance.signature).toMatchObject({
      scheme: 'JWS-ES256',
      key_id: signingKeyId,
      signed_message: signedMessage,
    });

    const fetched = await SELF.fetch(`http://localhost/api/messages/${message.id}`, {
      headers: authHeaders(),
    });
    expect(fetched.status).toBe(200);
    expect((await fetched.json() as SignedReplyResponse).metadata.provenance)
      .toEqual(message.metadata.provenance);
  });

  it('rejects unsigned messages from a token that has a signing key', async () => {
    const response = await reply({ body: 'Unsigned downgrade' });
    expect(response.status).toBe(401);
    expect(await response.text()).toBe('signed message required');
  });

  it('rejects an outer body that does not match the signed payload', async () => {
    const signedMessage = await signReply('Approve exactly this', crypto.randomUUID());
    const response = await reply({ body: 'Tampered body', signed_message: signedMessage });
    expect(response.status).toBe(401);
    expect(await response.text()).toBe('signed message does not match request');
  });

  it('returns the original reply when the signed message is replayed', async () => {
    const signedMessage = await signReply('Idempotent approval', crypto.randomUUID());
    const first = await reply({ body: 'Idempotent approval', signed_message: signedMessage });
    expect(first.status).toBe(201);
    const firstMessage = await first.json() as { id: string };
    const replay = await reply({ body: 'Idempotent approval', signed_message: signedMessage });
    expect(replay.status).toBe(200);
    expect((await replay.json() as { id: string }).id).toBe(firstMessage.id);
  });
});

async function pairSigningClient(): Promise<{
  token: string;
  signingKeyId: string;
  privateKey: CryptoKey;
}> {
  const issued = await SELF.fetch('http://localhost/api/boss/pairing', {
    method: 'POST',
    headers: bossHeaders(ROOT_TOKEN),
  });
  const { code } = await issued.json() as { code: string };
  const keys = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify'],
  );
  const publicKey = base64Url(new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey)));
  const proof = base64Url(new Uint8Array(await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    keys.privateKey,
    pairingProof(code, 'ios', publicKey).buffer as ArrayBuffer,
  )));
  const response = await SELF.fetch('http://localhost/api/pairing/redeem', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code,
      device_label: 'Signed iPhone',
      signing: { algorithm: 'ES256', client_kind: 'ios', public_key: publicKey, proof },
    }),
  });
  expect(response.status).toBe(200);
  const grant = await response.json() as { token: string; signing_key_id: string };
  return { token: grant.token, signingKeyId: grant.signing_key_id, privateKey: keys.privateKey };
}

async function signReply(body: string, messageId: string): Promise<string> {
  const header = base64Url(encoder.encode(JSON.stringify({
    alg: 'ES256', kid: signingKeyId, typ: 'hiboss-message+jws',
  })));
  const payload = base64Url(encoder.encode(JSON.stringify({
    version: 1,
    purpose: 'hiboss.boss-message',
    message_id: messageId,
    issued_at: Math.floor(Date.now() / 1000),
    boss_id: bossId,
    action: { kind: 'reply', message_id: PARENT_ID },
    body,
  })));
  const input = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, signingKey, encoder.encode(input),
  );
  return `${input}.${base64Url(new Uint8Array(signature))}`;
}

function reply(payload: Record<string, unknown>): Promise<Response> {
  return SELF.fetch(`http://localhost/api/boss/messages/${PARENT_ID}/reply`, {
    method: 'POST',
    headers: bossHeaders(signedToken),
    body: JSON.stringify(payload),
  });
}

function bossHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

function pairingProof(code: string, clientKind: string, publicKey: string): Uint8Array {
  return encoder.encode(`hiboss-pair-v1\n${code}\n${clientKind}\n${publicKey}`);
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

interface SignedReplyResponse {
  id: string;
  body: string;
  metadata: {
    source: string;
    provenance: {
      source: string;
      signature: Record<string, unknown>;
    };
  };
}
