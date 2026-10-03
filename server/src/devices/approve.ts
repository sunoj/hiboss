// Atomic approval and rejection of device join requests.
// Exports approveJoin and rejectJoin; one D1 batch creates the device, every
// profile's agent and its first key, or nothing at all.
import { prepareKey } from '../agent-keys/repository';
import type { KeyActor } from '../agent-keys/types';
import { parseStoredProfiles, type DeliveredProfile, type Delivery, type JoinRequestRow } from './types';

export type ApproveOutcome =
  | { ok: true; deviceId: string; agents: Array<{ profile: string; name: string; agent_id: string }> }
  | { ok: false; status: 404 | 409; error: string };

export interface ApproveOptions { approverBossId?: string; firstOnly?: boolean }

interface PreparedAgent extends DeliveredProfile { keyId: string; keyStatement: D1PreparedStatement }

// Every write after the claim runs only if this approval's delivery is the stored one.
const CLAIMED = 'EXISTS (SELECT 1 FROM join_requests WHERE id = ? AND delivery = ?)';

export async function approveJoin(db: D1Database, requestId: string, actor: KeyActor,
  options: ApproveOptions = {}): Promise<ApproveOutcome> {
  const row = await db.prepare('SELECT * FROM join_requests WHERE id = ?').bind(requestId).first<JoinRequestRow>();
  if (!row) return { ok: false, status: 404, error: 'join request not found' };
  if (row.status !== 'pending') return { ok: false, status: 409, error: `join request already ${row.status}` };
  const profiles = parseStoredProfiles(row.profiles);
  if (profiles.length === 0) return { ok: false, status: 409, error: 'join request has no valid profiles' };
  const deviceId = row.device_id ?? `d_${crypto.randomUUID().replaceAll('-', '')}`;
  const agents: PreparedAgent[] = [];
  for (const profile of profiles) {
    const agentId = crypto.randomUUID().replaceAll('-', '');
    const key = await prepareKey(db, agentId, `device:${row.device_label}`.slice(0, 100));
    agents.push({ ...profile, agent_id: agentId, key: key.key, keyId: key.id, keyStatement: key.statement });
  }
  const delivery: Delivery = { device_id: deviceId, profiles: agents.map(({ profile, name, agent_id, key }) => ({ profile, name, agent_id, key })) };
  const deliveryJson = JSON.stringify(delivery);
  const statements = [
    db.prepare(`UPDATE join_requests SET status = 'approved', delivery = ?, updated_at = datetime('now')
      WHERE id = ? AND status = 'pending' AND (? = 0 OR NOT EXISTS (SELECT 1 FROM api_keys))`)
      .bind(deliveryJson, requestId, Number(options.firstOnly ?? false)),
    ...(row.device_id ? [] : [db.prepare(`INSERT INTO devices (id, label, host) SELECT ?, ?, ? WHERE ${CLAIMED}`)
      .bind(deviceId, row.device_label, row.device_host, requestId, deliveryJson)]),
    db.prepare('UPDATE join_requests SET device_id = ? WHERE id = ? AND delivery = ?').bind(deviceId, requestId, deliveryJson),
    ...agents.flatMap(agent => agentStatements(db, agent, deviceId, actor, options.approverBossId, [requestId, deliveryJson])),
  ];
  try {
    const [claim] = await db.batch(statements);
    if (!claim.meta.changes) return { ok: false, status: 409, error: 'join request already processed' };
  } catch (error) {
    if (error instanceof Error && /UNIQUE/.test(error.message)) {
      return { ok: false, status: 409, error: 'an agent with one of these names already exists' };
    }
    throw error;
  }
  return { ok: true, deviceId, agents: agents.map(({ profile, name, agent_id }) => ({ profile, name, agent_id })) };
}

export async function rejectJoin(db: D1Database, requestId: string): Promise<{ ok: true } | { ok: false; status: 404 | 409; error: string }> {
  const row = await db.prepare('SELECT status FROM join_requests WHERE id = ?').bind(requestId).first<{ status: string }>();
  if (!row) return { ok: false, status: 404, error: 'join request not found' };
  const result = await db.prepare("UPDATE join_requests SET status = 'rejected', updated_at = datetime('now') WHERE id = ? AND status = 'pending'")
    .bind(requestId).run();
  return result.meta.changes ? { ok: true } : { ok: false, status: 409, error: `join request already ${row.status}` };
}

function agentStatements(db: D1Database, agent: PreparedAgent, deviceId: string, actor: KeyActor,
  approverBossId: string | undefined, claim: [string, string]): D1PreparedStatement[] {
  // Plain INSERT: a taken name raises UNIQUE and rolls the whole batch back.
  const list = [
    db.prepare(`INSERT INTO api_keys (id, name, device_id) SELECT ?, ?, ? WHERE ${CLAIMED}`)
      .bind(agent.agent_id, agent.name, deviceId, ...claim),
    agent.keyStatement,
    db.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
      SELECT ?, ?, 'agent_key.mint', 'agent_key', ?, ? WHERE ${CLAIMED}`)
      .bind(actor.type, actor.id, agent.keyId, JSON.stringify({ agent_id: agent.agent_id }), ...claim),
  ];
  if (approverBossId) {
    list.push(db.prepare(`INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) SELECT ?, ? WHERE ${CLAIMED}`)
      .bind(approverBossId, agent.agent_id, ...claim));
  }
  return list;
}
