// Issues independent bearer tokens for boss identities.
// Exports issueBossToken for admin token generation and QR redemption.
// Depends on the shared Env binding and SHA-256 auth helper.

import type { Env } from './types';
import { hashApiKey } from './middleware/auth';

const TOKEN_BYTES = 32;

export async function issueBossToken(env: Env, bossId: string, label: string): Promise<string> {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('');
  const token = `hb_boss_${hex}`;
  const tokenHash = await hashApiKey(token);
  await env.DB.prepare('INSERT INTO boss_tokens (boss_id, label, token_hash) VALUES (?, ?, ?)')
    .bind(bossId, label, tokenHash)
    .run();
  return token;
}
