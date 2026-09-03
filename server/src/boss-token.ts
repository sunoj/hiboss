// Issues independent bearer tokens for boss identities.
// Exports issueBossToken for admin token generation and QR redemption.
// Depends on the shared Env binding and SHA-256 auth helper.

import type { Env } from './types';
import { hashApiKey } from './middleware/auth';
import type { RegisteredSigningKey } from './message-security';

const TOKEN_BYTES = 32;

export interface BossTokenGrant {
  readonly token: string;
  readonly tokenId: string;
}

export async function issueBossToken(
  env: Env,
  bossId: string,
  label: string,
  signingKey?: RegisteredSigningKey,
): Promise<BossTokenGrant> {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('');
  const token = `hb_boss_${hex}`;
  const tokenId = crypto.randomUUID().replaceAll('-', '');
  const tokenHash = await hashApiKey(token);
  const tokenInsert = env.DB.prepare(
    'INSERT INTO boss_tokens (id, boss_id, label, token_hash) VALUES (?, ?, ?, ?)',
  ).bind(tokenId, bossId, label, tokenHash);
  if (!signingKey) {
    await tokenInsert.run();
    return { token, tokenId };
  }
  const keyInsert = env.DB.prepare(
    `INSERT INTO boss_signing_keys
       (id, boss_id, boss_token_id, algorithm, client_kind, public_key)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(
    signingKey.id, bossId, tokenId, signingKey.algorithm,
    signingKey.clientKind, signingKey.publicKey,
  );
  await env.DB.batch([tokenInsert, keyInsert]);
  return { token, tokenId };
}
