// Issues independent bearer tokens for boss identities.
// Exports issueBossToken, and guarded issuance statements for QR redemption.
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

/** A SQL condition every insert of an issuance carries, so the grant commits only while it holds. */
export interface IssuanceGuard {
  readonly sql: string;
  readonly binds: readonly unknown[];
}

export async function issueBossToken(
  env: Env,
  bossId: string,
  label: string,
  signingKey?: RegisteredSigningKey,
  client?: ClientRegistration,
): Promise<BossTokenGrant> {
  const issuance = await bossTokenStatements(env, bossId, label, signingKey, client);
  await env.DB.batch([...issuance.statements]);
  return issuance.grant;
}

/** The statements of one issuance, for callers that batch them behind their own claim. */
export async function bossTokenStatements(
  env: Env,
  bossId: string,
  label: string,
  signingKey?: RegisteredSigningKey,
  client?: ClientRegistration,
  guard: IssuanceGuard = { sql: '1 = 1', binds: [] },
): Promise<{ grant: BossTokenGrant; statements: readonly D1PreparedStatement[] }> {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('');
  const token = `hb_boss_${hex}`;
  const tokenId = crypto.randomUUID().replaceAll('-', '');
  const tokenHash = await hashApiKey(token);
  const clientId = client ? crypto.randomUUID() as ClientId : null;
  const insert = (table: string, values: readonly unknown[]): D1PreparedStatement => env.DB.prepare(
    `INSERT INTO ${table} SELECT ${values.map(() => '?').join(', ')} WHERE ${guard.sql}`,
  ).bind(...values, ...guard.binds);
  const statements: D1PreparedStatement[] = [];
  if (client) statements.push(insert('boss_clients (id, boss_id, kind, label)', [clientId, bossId, client.kind, client.label]));
  statements.push(insert('boss_tokens (id, boss_id, label, token_hash, client_id)', [tokenId, bossId, label, tokenHash, clientId]));
  if (signingKey) statements.push(insert(
    'boss_signing_keys (id, boss_id, boss_token_id, algorithm, client_kind, public_key, client_id)',
    [signingKey.id, bossId, tokenId, signingKey.algorithm, signingKey.clientKind, signingKey.publicKey, clientId],
  ));
  return { grant: { token, tokenId, clientId }, statements };
}
