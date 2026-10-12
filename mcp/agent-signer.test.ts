// Round-trips MCP agent signing through the MCP verifier using a CLI-format key file.
// The key file holds the exact PKCS#8 layout the Rust CLI writes (ring's P-256 template).
// Depends on Bun test, Web Crypto, node fs/os, agent-signer and message-security.

import { describe, expect, it } from 'bun:test';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { signAction, signSend, signerPath } from './agent-signer.js';
import { assuranceLabel, verifyMessage, type VerifiableMessage } from './message-security.js';

const SERVER = 'https://hiboss.invalid';
const RING_PREFIX = '308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420';

/** Writes a CLI key file whose PKCS#8 bytes follow ring's template, returning env and public key. */
async function cliKeyFile(bearer: string): Promise<{ env: NodeJS.ProcessEnv; publicKey: string; keyId: string }> {
  const env = { HIBOSS_CONFIG: join(mkdtempSync(join(tmpdir(), 'hiboss-mcp-sign-')), 'config.json') };
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign']) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
  const raw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey) as ArrayBuffer);
  const der = Buffer.concat([Buffer.from(RING_PREFIX, 'hex'), Buffer.from(jwk.d ?? '', 'base64url'),
    Buffer.from('a144034200', 'hex'), Buffer.from(raw)]);
  const keyId = Buffer.from(await crypto.subtle.digest('SHA-256', raw)).toString('base64url');
  const path = signerPath(bearer, env);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify({ version: 1, agent_id: 'agent-1', agent_key_id: 'cred-1', key_id: keyId,
    pkcs8: der.toString('base64url') }));
  return { env, publicKey: Buffer.from(raw).toString('base64url'), keyId };
}

function stored(request: Record<string, unknown>, key: { publicKey: string; keyId: string },
  direction: string, overrides: Partial<VerifiableMessage> = {}): VerifiableMessage {
  const metadata: Record<string, unknown> = { ...(request.metadata as Record<string, unknown> ?? {}), source: 'agent',
    provenance: { version: 1, source: 'agent', actor: { kind: 'agent', id: 'agent-1' },
      signature: { scheme: 'JWS-ES256', key_id: key.keyId, public_key: key.publicKey, signed_message: request.signed_message } } };
  if (request.options) metadata.options = request.options;
  return { id: 'msg-1', agent_id: 'agent-1', direction, body: request.body as string, metadata,
    created_at: new Date().toISOString(), ...overrides };
}

describe('MCP agent signing', () => {
  it('signs a send with a CLI key file and verifies as agent/verified', async () => {
    const key = await cliKeyFile('hb_mcp_send');
    const request = await signSend(SERVER, 'hb_mcp_send', { body: '  Ready?  ', mode: 'blocking', options: [' Yes ', 'No'],
      metadata: { content: '## Plan', source: 'ios' } }, key.env);
    expect(request.body).toBe('Ready?');
    expect(request.options).toEqual(['Yes', 'No']);
    const assurance = await verifyMessage(stored(request, key, 'agent_to_boss'));
    expect(assuranceLabel(assurance)).toBe('agent/verified');
  });

  it('binds the resolved recipient and rejects tampering, re-addressing and a forged sender', async () => {
    const key = await cliKeyFile('hb_mcp_tamper');
    const realFetch = globalThis.fetch;
    globalThis.fetch = (async () => Response.json({ agent_id: 'agent-2', session_id: 'sess-2' })) as unknown as typeof fetch;
    const request = await signSend(SERVER, 'hb_mcp_tamper', { body: 'Rebased', to: 'otter-2' }, key.env)
      .finally(() => { globalThis.fetch = realFetch; });
    const toB = { target_agent_id: 'agent-2', target_session_id: 'sess-2' };
    await expect(verifyMessage(stored(request, key, 'agent_to_agent', toB))).resolves.toMatchObject({ kind: 'verified' });
    await expect(verifyMessage(stored(request, key, 'agent_to_agent', { ...toB, body: 'Force-pushed' }))).rejects.toThrow('body mismatch');
    await expect(verifyMessage(stored(request, key, 'agent_to_agent', { target_agent_id: 'agent-3', target_session_id: 'sess-3' })))
      .rejects.toThrow('does not match');
    await expect(verifyMessage(stored(request, key, 'agent_to_boss'))).rejects.toThrow('does not match');
    await expect(verifyMessage(stored(request, key, 'agent_to_agent', { ...toB, agent_id: 'agent-2' }))).rejects.toThrow('does not match');
  });

  it('rejects a recipient, options or a file added to a row whose signature has none', async () => {
    const key = await cliKeyFile('hb_mcp_gain');
    const request = await signSend(SERVER, 'hb_mcp_gain', { body: 'Status' }, key.env);
    await expect(verifyMessage(stored(request, key, 'agent_to_boss', { target_agent_id: 'agent-3' }))).rejects.toThrow('does not match');
    for (const [field, value] of [['options', ['Approve deployment', 'Reject']], ['file_url', 'https://x/evil.sh']] as const) {
      const row = stored(request, key, 'agent_to_boss');
      (row.metadata as Record<string, unknown>)[field] = value;
      await expect(verifyMessage(row)).rejects.toThrow(`signed ${field} mismatch`);
    }
  });

  it('requires a valid creation time on a signed row', async () => {
    const key = await cliKeyFile('hb_mcp_time');
    const request = await signSend(SERVER, 'hb_mcp_time', { body: 'Status' }, key.env);
    const sqlite = new Date().toISOString().slice(0, 19).replace('T', ' ');
    await expect(verifyMessage(stored(request, key, 'agent_to_boss', { created_at: sqlite }))).resolves.toMatchObject({ kind: 'verified' });
    for (const bad of [null, '', 'not-a-date']) {
      await expect(verifyMessage(stored(request, key, 'agent_to_boss', { created_at: bad }))).rejects.toThrow('created_at');
    }
  });

  it('binds a reply to its parent and leaves requests unsigned without a key', async () => {
    const key = await cliKeyFile('hb_mcp_reply');
    const reply = await signAction('hb_mcp_reply', { body: 'Done' }, { kind: 'reply', message_id: 'parent-1', audience: { kind: 'boss' } },
      key.env);
    await expect(verifyMessage(stored(reply, key, 'agent_to_boss', { reply_to: 'parent-1' }))).resolves.toMatchObject({ kind: 'verified' });
    await expect(verifyMessage(stored(reply, key, 'agent_to_boss', { reply_to: 'parent-2' }))).rejects.toThrow('does not match');
    const unsigned = await signSend(SERVER, 'hb_no_key', { body: 'plain' }, key.env);
    expect(unsigned.signed_message).toBeUndefined();
  });
});
