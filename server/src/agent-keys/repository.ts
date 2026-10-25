// Audited credential persistence and guarded revocation.
// Exports listKeys, mintKey, revokeKey; depends on D1 and SHA-256 hashing.
import { hashApiKey } from '../middleware/auth';
import { mayMint } from './boss-access';
import { KEY_COLUMNS, type AgentKey, type KeyActor } from './types';

export function keyAudit(db: D1Database, actor: KeyActor, action: string, id: string, agentId: string): D1PreparedStatement {
  return db.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
    VALUES (?, ?, ?, 'agent_key', ?, ?)`)
    .bind(actor.type, actor.id, action, id, JSON.stringify({ agent_id: agentId }));
}

export async function listKeys(db: D1Database, agentId: string, actor: KeyActor): Promise<AgentKey[]> {
  const [rows] = await db.batch<AgentKey>([
    db.prepare(`SELECT ${KEY_COLUMNS} FROM agent_keys WHERE agent_id = ? ORDER BY created_at DESC, id`).bind(agentId),
    keyAudit(db, actor, 'agent_key.list', agentId, agentId),
  ]);
  return rows.results;
}

export async function prepareKey(db: D1Database, agentId: string, label: string, mintedBy: string | null = null): Promise<{
  id: string; key: string; statement: D1PreparedStatement;
}> {
  const id = crypto.randomUUID();
  const key = `hb_${Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('')}`;
  const hash = await hashApiKey(key);
  // A boss mint commits only while that boss may still mint, so it cannot outrun a concurrent sweep.
  const statement = db.prepare(`INSERT INTO agent_keys (id, agent_id, key_hash, label, minted_by_boss_id)
    SELECT ?1, id, ?2, ?3, ?4 FROM api_keys WHERE id = ?5 AND (?4 IS NULL OR ${mayMint('?4', '?5')})
    RETURNING ${KEY_COLUMNS}`)
    .bind(id, hash, label, mintedBy, agentId);
  return { id, key, statement };
}

/** Returns null when the agent is gone or a boss actor lost the right to mint for it. */
export async function mintKey(db: D1Database, agentId: string, label: string, actor: KeyActor): Promise<(AgentKey & { key: string }) | null> {
  const key = await prepareKey(db, agentId, label, actor.type === 'boss' ? actor.id : null);
  const [rows] = await db.batch<AgentKey>([key.statement, db.prepare(`INSERT INTO audit_log
    (actor_type, actor_id, action, resource_type, resource_id, details)
    SELECT ?, ?, 'agent_key.mint', 'agent_key', ?, ? WHERE changes() > 0`)
    .bind(actor.type, actor.id, key.id, JSON.stringify({ agent_id: agentId }))]);
  return rows.results[0] ? { ...rows.results[0], key: key.key } : null;
}

export async function revokeKey(db: D1Database, agentId: string, id: string, actor: KeyActor,
  currentId: string | null): Promise<'revoked' | 'missing' | 'last'> {
  const key = await db.prepare('SELECT revoked_at FROM agent_keys WHERE id = ? AND agent_id = ?')
    .bind(id, agentId).first<{ revoked_at: string | null }>();
  if (!key) return 'missing';
  if (key.revoked_at) return 'revoked';
  const [result] = await db.batch([
    db.prepare(`UPDATE agent_keys SET revoked_at = datetime('now') WHERE id = ? AND agent_id = ?
      AND revoked_at IS NULL AND (? IS NULL OR id != ? OR
        EXISTS (SELECT 1 FROM agent_keys other WHERE other.agent_id = ? AND other.id != ? AND other.revoked_at IS NULL))`)
      .bind(id, agentId, currentId, currentId, agentId, id),
    db.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
      SELECT ?, ?, 'agent_key.revoke', 'agent_key', ?, ? WHERE changes() > 0`)
      .bind(actor.type, actor.id, id, JSON.stringify({ agent_id: agentId })),
  ]);
  return result.meta.changes ? 'revoked' : 'last';
}
