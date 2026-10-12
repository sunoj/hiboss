// Agent signing-key registry: proof-checked enrollment, endorsement and boss reset.
// Exports live-key lookups, enrollAgentSigningKey and revokeAgentSigningKey.
// Depends on D1, the ES256 proof helper and compact JWS verification.

import type { Env } from '../types';
import { verifyKeyProof } from './crypto';
import { isFresh, peekJwsKeyId, verifyCompactJws } from './jws';

export const AGENT_KEY_DOMAIN = 'hiboss-agent-key-v1';
export const ENDORSEMENT_TYPE = 'hiboss-agent-key+jws';
const ENDORSEMENT_PURPOSE = 'hiboss.agent-key-endorsement';

export interface AgentSigningKey {
  readonly id: string;
  readonly key_id: string;
  readonly agent_id: string;
  readonly agent_key_id: string;
  readonly public_key: string;
  readonly enrolled_via: 'first_use' | 'endorsed';
  readonly created_at: string;
}

export interface EnrollmentInput {
  readonly agentId: string;
  readonly agentKeyId: string;
  readonly publicKey: unknown;
  readonly proof: unknown;
  readonly endorsement: unknown;
}

export type EnrollmentResult =
  | { readonly ok: true; readonly key: AgentSigningKey; readonly created: boolean }
  | { readonly ok: false; readonly status: 400 | 401 | 403 | 409; readonly error: string };

const LIVE = `s.revoked_at IS NULL AND k.revoked_at IS NULL`;
const COLUMNS = 's.id, s.key_id, s.agent_id, s.agent_key_id, s.public_key, s.enrolled_via, s.created_at';

/** A Worker deployed before migration 0055 has no keys to enforce; any other error propagates. */
async function beforeMigration<T>(query: Promise<T>, fallback: T): Promise<T> {
  try {
    return await query;
  } catch (error) {
    if (error instanceof Error && /no such table: (main\.)?agent_(signing_)?keys/.test(error.message)) return fallback;
    throw error;
  }
}

export function findLiveKeyForCredential(env: Env, agentKeyId: string): Promise<AgentSigningKey | null> {
  return beforeMigration(env.DB.prepare(`SELECT ${COLUMNS} FROM agent_signing_keys s JOIN agent_keys k ON k.id = s.agent_key_id
    WHERE s.agent_key_id = ? AND ${LIVE}`).bind(agentKeyId).first<AgentSigningKey>(), null);
}

export async function listLiveAgentKeys(env: Env, agentId: string): Promise<AgentSigningKey[]> {
  const rows = await beforeMigration(env.DB.prepare(`SELECT ${COLUMNS} FROM agent_signing_keys s JOIN agent_keys k ON k.id = s.agent_key_id
    WHERE s.agent_id = ? AND ${LIVE} ORDER BY s.created_at DESC`).bind(agentId).all<AgentSigningKey>(), null);
  return rows?.results ?? [];
}

/** Every key a boss has not reset, including ones whose credential was revoked (they still bind the agent). */
export async function listUnresetAgentKeys(env: Env, agentId: string): Promise<(AgentSigningKey & { credential_live: number })[]> {
  const rows = await beforeMigration(env.DB.prepare(`SELECT ${COLUMNS}, (k.revoked_at IS NULL) AS credential_live
    FROM agent_signing_keys s JOIN agent_keys k ON k.id = s.agent_key_id
    WHERE s.agent_id = ? AND s.revoked_at IS NULL ORDER BY s.created_at DESC`)
    .bind(agentId).all<AgentSigningKey & { credential_live: number }>(), null);
  return rows?.results ?? [];
}

/**
 * True once the agent enrolled any key that a boss has not reset. Credential revocation does
 * not clear it: a bearer holder could otherwise revoke every signing credential and downgrade.
 */
export async function agentRequiresSignature(env: Env, agentId: string): Promise<boolean> {
  const row = await beforeMigration(env.DB.prepare(`SELECT 1 AS required FROM agent_signing_keys
    WHERE agent_id = ? AND revoked_at IS NULL LIMIT 1`).bind(agentId).first<{ required: number }>(), null);
  return row !== null;
}

export async function enrollAgentSigningKey(env: Env, input: EnrollmentInput): Promise<EnrollmentResult> {
  if (typeof input.publicKey !== 'string' || typeof input.proof !== 'string') {
    return { ok: false, status: 400, error: 'public_key and proof are required' };
  }
  const proofInput = `${AGENT_KEY_DOMAIN}\n${input.agentKeyId}\n${input.agentId}\n${input.publicKey}`;
  const keyId = await verifyKeyProof(proofInput, input.publicKey, input.proof);
  if (!keyId) return { ok: false, status: 401, error: 'invalid key proof' };
  const current = await findLiveKeyForCredential(env, input.agentKeyId);
  if (current) {
    return current.key_id === keyId
      ? { ok: true, key: current, created: false }
      : { ok: false, status: 409, error: 'this credential already has a different signing key' };
  }
  let endorsedBy: string | null = null;
  if (await agentRequiresSignature(env, input.agentId)) {
    endorsedBy = await verifyEndorsement(input, keyId, await listLiveAgentKeys(env, input.agentId));
    if (!endorsedBy) {
      return { ok: false, status: 403, error: 'endorsement required: sign with an enrolled key of this agent, or ask the boss to reset its signing keys' };
    }
  }
  return insertKey(env, input, keyId, endorsedBy);
}

async function insertKey(env: Env, input: EnrollmentInput, keyId: string, endorsedBy: string | null): Promise<EnrollmentResult> {
  const via = endorsedBy ? 'endorsed' : 'first_use';
  const [inserted] = await env.DB.batch<AgentSigningKey>([
    env.DB.prepare(`INSERT INTO agent_signing_keys (key_id, agent_id, agent_key_id, algorithm, public_key, enrolled_via, endorsed_by)
      SELECT ?, ?, ?, 'ES256', ?, ?, ? WHERE NOT EXISTS (
        SELECT 1 FROM agent_signing_keys WHERE agent_key_id = ? AND revoked_at IS NULL)
      AND (? IS NOT NULL OR NOT EXISTS (
        SELECT 1 FROM agent_signing_keys WHERE agent_id = ? AND revoked_at IS NULL))
      RETURNING id, key_id, agent_id, agent_key_id, public_key, enrolled_via, created_at`)
      .bind(keyId, input.agentId, input.agentKeyId, input.publicKey, via, endorsedBy, input.agentKeyId, endorsedBy, input.agentId),
    env.DB.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
      SELECT 'agent', ?, 'agent_signing_key.enroll', 'agent_signing_key', ?, ?
      WHERE changes() > 0`).bind(input.agentId, keyId, JSON.stringify({ agent_key_id: input.agentKeyId, via })),
  ]);
  const key = inserted?.results?.[0];
  if (!key) return { ok: false, status: 409, error: 'enrollment raced with another enrollment; retry' };
  return { ok: true, key, created: true };
}

async function verifyEndorsement(input: EnrollmentInput, newKeyId: string,
  live: readonly AgentSigningKey[]): Promise<string | null> {
  if (typeof input.endorsement !== 'string' || !input.endorsement) return null;
  const signer = live.find(key => key.key_id === peekJwsKeyId(input.endorsement as string));
  if (!signer) return null;
  const payload = await verifyCompactJws(
    input.endorsement, { keyId: signer.key_id, publicKey: signer.public_key }, ENDORSEMENT_TYPE,
  );
  if (!payload) return null;
  const issuedAt = payload['issued_at'];
  const valid = payload['version'] === 1
    && payload['purpose'] === ENDORSEMENT_PURPOSE
    && payload['agent_id'] === input.agentId
    && payload['agent_key_id'] === input.agentKeyId
    && payload['key_id'] === newKeyId
    && typeof issuedAt === 'number' && Number.isInteger(issuedAt) && isFresh(issuedAt);
  return valid ? signer.key_id : null;
}

/** Boss reset: revokes one live key (or all with keyId null), returning the count revoked. */
export async function revokeAgentSigningKey(env: Env, agentId: string, keyId: string | null,
  actor: { type: 'boss'; id: string }): Promise<number> {
  const [revoked] = await env.DB.batch([
    env.DB.prepare(`UPDATE agent_signing_keys SET revoked_at = datetime('now')
      WHERE agent_id = ? AND revoked_at IS NULL AND (? IS NULL OR key_id = ?)`).bind(agentId, keyId, keyId),
    env.DB.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
      SELECT ?, ?, 'agent_signing_key.revoke', 'agent', ?, ? WHERE changes() > 0`)
      .bind(actor.type, actor.id, agentId, JSON.stringify({ key_id: keyId ?? 'all' })),
  ]);
  return revoked?.meta.changes ?? 0;
}
