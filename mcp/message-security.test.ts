// Verifies MCP-side signature enforcement before content reaches model context.
// Covers valid native signatures, body tampering, and unsupported Discord signing.
// Depends on Bun test, Web Crypto P-256, and the message-security feature.

import { describe, expect, it } from 'bun:test';
import { verifyMessage } from './message-security.js';
import { setPinsForTest } from './boss-pins.js';

const encoder = new TextEncoder();

describe('MCP message verification', () => {
  it('verifies an ES256 iOS reply', async () => {
    await expect(verifyMessage(await signedMessage('Approve', 'Approve'))).resolves.toMatchObject({
      kind: 'verified', source: 'ios',
    });
  });

  it('rejects a body changed after signing', async () => {
    await expect(verifyMessage(await signedMessage('Approve', 'Tampered')))
      .rejects.toThrow('body mismatch');
  });

  it('rejects form answers changed after signing', async () => {
    const signed = await signedMessage('Submitted', 'Submitted', { order: ['b', 'a'] });
    await expect(verifyMessage(withAnswers(signed, { order: ['b', 'a'] }))).resolves.toMatchObject({ kind: 'verified' });
    await expect(verifyMessage(withAnswers(signed, { order: ['a', 'b'] }))).rejects.toThrow('answers mismatch');
    const plain = await signedMessage('Submitted', 'Submitted');
    await expect(verifyMessage(withAnswers(plain, { order: ['a'] }))).rejects.toThrow('answers mismatch');
  });

  it('verifies against a pinned key and refuses an unpinned one once anything is pinned', async () => {
    const message = await signedMessage('Approve', 'Approve');
    const signature = ((message.metadata as Record<string, any>).provenance.signature) as Record<string, string>;
    setPinsForTest([{ boss_id: 'boss-1', keys: [{ key_id: signature.key_id, public_key: signature.public_key }] }]);
    try {
      await expect(verifyMessage(message)).resolves.toMatchObject({ kind: 'verified' });
      await expect(verifyMessage(await signedMessage('Approve', 'Approve'))).rejects.toThrow('not pinned');
      setPinsForTest([{ boss_id: 'boss-1', keys: [], revoked: [{ key_id: signature.key_id,
        revoked_at: '2026-01-01T00:00:00Z', public_key: signature.public_key }] }]);
      await expect(verifyMessage(message)).rejects.toThrow('revoked');
      setPinsForTest([{ boss_id: 'boss-1', keys: [], revoked: [{ key_id: signature.key_id,
        revoked_at: '2026-11-28 00:00:00', public_key: signature.public_key }] }]);
      await expect(verifyMessage(message)).resolves.toMatchObject({ kind: 'verified' });
      setPinsForTest([], true);
      await expect(verifyMessage(await signedMessage('Approve', 'Approve'))).rejects.toThrow('not pinned');
    } finally {
      setPinsForTest(undefined);
    }
  });

  it('accepts Discord with explicit unsupported attribution', async () => {
    await expect(verifyMessage({
      id: 'discord-1',
      body: 'Provider message',
      direction: 'boss_to_agent',
      metadata: {
        source: 'discord',
        provenance: {
          version: 1,
          source: 'discord',
          signature: { status: 'unsupported' },
        },
      },
    })).resolves.toEqual({ kind: 'attributed', source: 'discord', status: 'unsupported' });
  });
});

function withAnswers(message: Record<string, unknown>, answers: unknown): Record<string, unknown> {
  const metadata = message.metadata as Record<string, unknown>;
  return { ...message, metadata: { ...metadata, answers } };
}

async function signedMessage(
  signedBody: string, body: string, answers?: unknown,
): Promise<Record<string, unknown>> {
  const keys = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'],
  );
  const rawPublicKey = new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey));
  const publicKey = encode(rawPublicKey);
  const keyId = encode(new Uint8Array(await crypto.subtle.digest('SHA-256', rawPublicKey)));
  const header = encodeJson({ alg: 'ES256', kid: keyId, typ: 'hiboss-message+jws' });
  const payload = encodeJson({
    version: 1,
    purpose: 'hiboss.boss-message',
    message_id: '12345678-1234-1234-1234-123456789abc',
    issued_at: 1_788_454_800,
    boss_id: 'boss-1',
    action: { kind: 'reply', message_id: 'parent-1' },
    body: signedBody,
    ...(answers === undefined ? {} : { answers }),
  });
  const input = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey, encoder.encode(input),
  );
  return {
    id: 'reply-1', body, direction: 'boss_to_agent', reply_to: 'parent-1',
    metadata: {
      source: 'ios',
      provenance: {
        version: 1,
        source: 'ios',
        actor: { kind: 'boss', id: 'boss-1' },
        signature: {
          scheme: 'JWS-ES256', key_id: keyId, public_key: publicKey,
          signed_message: `${input}.${encode(new Uint8Array(signature))}`,
        },
      },
    },
  };
}

function encodeJson(value: Record<string, unknown>): string {
  return encode(encoder.encode(JSON.stringify(value)));
}

function encode(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64url');
}
