// Audited credential persistence and guarded revocation.
// Exports listKeys, mintKey, revokeKey; depends on D1 and SHA-256 hashing.
import { hashApiKey } from '../middleware/auth';
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

export async function prepareKey(db: D1Database, agentId: string, label: string): Promise<{
  id: string; key: string; statement: D1PreparedStatement;
}> {
  const id = crypto.randomUUID();
  const key = `hb_${Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('')}`;
  const hash = await hashApiKey(key);
  const statement = db.prepare(`INSERT INTO agent_keys (id, agent_id, key_hash, label)
    SELECT ?, id, ?, ? FROM api_keys WHERE id = ? RETURNING ${KEY_COLUMNS}`)
    .bind(id, hash, label, agentId);
  return { id, key, statement };
}

export async function mintKey(db: D1Database, agentId: string, label: string, actor: KeyActor): Promise<AgentKey & { key: string }> {
  const key = await prepareKey(db, agentId, label);
  const [rows] = await db.batch<AgentKey>([key.statement, keyAudit(db, actor, 'agent_key.mint', key.id, agentId)]);
  if (!rows.results[0]) throw new Error('agent missing during key creation');
  return { ...rows.results[0], key: key.key };
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
