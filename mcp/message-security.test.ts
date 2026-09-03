// Verifies MCP-side signature enforcement before content reaches model context.
// Covers valid native signatures, body tampering, and unsupported Discord signing.
// Depends on Bun test, Web Crypto P-256, and the message-security feature.

import { describe, expect, it } from 'bun:test';
import { verifyMessage } from './message-security.js';

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

async function signedMessage(signedBody: string, body: string): Promise<Record<string, unknown>> {
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
