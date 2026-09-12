// Atomic creation of an agent identity and its first independent credential.
// Exports createAgent; depends on D1 and audited key preparation.
import { prepareKey } from './repository';
import type { KeyActor } from './types';

export async function createAgent(db: D1Database, name: string, actor: KeyActor,
  firstOnly = false): Promise<{ id: string; name: string; key: string } | null> {
  const id = crypto.randomUUID().replaceAll('-', '');
  const key = await prepareKey(db, id, 'initial');
  const [agents] = await db.batch<{ id: string; name: string }>([
    db.prepare(`INSERT INTO api_keys (id, name) SELECT ?, ?
      WHERE (? = 0 OR NOT EXISTS (SELECT 1 FROM api_keys))
      ON CONFLICT(name) DO NOTHING RETURNING id, name`).bind(id, name, Number(firstOnly)),
    key.statement,
    db.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
      SELECT ?, ?, 'agent_key.mint', 'agent_key', ?, ? WHERE EXISTS (SELECT 1 FROM agent_keys WHERE id = ?)`)
      .bind(actor.type, actor.id, key.id, JSON.stringify({ agent_id: id }), key.id),
  ]);
  return agents.results[0] ? { ...agents.results[0], key: key.key } : null;
}
