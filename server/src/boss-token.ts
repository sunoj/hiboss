// Issues independent bearer tokens for boss identities.
// Exports issueBossToken for admin token generation and QR redemption.
// Depends on the shared Env binding and SHA-256 auth helper.

import type { Env } from './types';
import { hashApiKey } from './middleware/auth';
import type { RegisteredSigningKey } from './message-security';

import type { ClientId, ClientRegistration } from './boss-clients/types';

const TOKEN_BYTES = 32;

export interface BossTokenGrant {
  readonly token: string;
  readonly tokenId: string;
  readonly clientId: ClientId | null;
}

export async function issueBossToken(
  env: Env,
  bossId: string,
  label: string,
  signingKey?: RegisteredSigningKey,
  client?: ClientRegistration,
): Promise<BossTokenGrant> {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('');
  const token = `hb_boss_${hex}`;
  const tokenId = crypto.randomUUID().replaceAll('-', '');
  const tokenHash = await hashApiKey(token);
  const clientId = client ? crypto.randomUUID() as ClientId : null;
  const statements: D1PreparedStatement[] = [];
  if (client) statements.push(env.DB.prepare(
    'INSERT INTO boss_clients (id, boss_id, kind, label) VALUES (?, ?, ?, ?)',
  ).bind(clientId, bossId, client.kind, client.label));
  const tokenInsert = env.DB.prepare(
    'INSERT INTO boss_tokens (id, boss_id, label, token_hash, client_id) VALUES (?, ?, ?, ?, ?)',
  ).bind(tokenId, bossId, label, tokenHash, clientId);
  statements.push(tokenInsert);
  if (signingKey) statements.push(env.DB.prepare(
    `INSERT INTO boss_signing_keys
       (id, boss_id, boss_token_id, algorithm, client_kind, public_key, client_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    signingKey.id, bossId, tokenId, signingKey.algorithm,
    signingKey.clientKind, signingKey.publicKey, clientId,
  ));
  await env.DB.batch(statements);
  return { token, tokenId, clientId };
}
