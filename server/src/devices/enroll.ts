// Creates device join requests and delivers approved keys exactly once.
// Exports createJoinRequest, pollJoinRequest and resolveDeviceProof.
// Depends on D1, SHA-256 hashing and the atomic approval in approve.ts.
import { hashApiKey } from '../middleware/auth';
import { approveJoin } from './approve';
import { verificationCode, type ConsumedInvite } from './invites';
import { parseStoredProfiles, type Delivery, type JoinPayload, type JoinRequestRow } from './types';

export type CreateOutcome =
  | { kind: 'created'; requestId: string; pollToken: string; status: 'pending' | 'approved'; delivery?: Delivery;
      verificationCode: string | null }
  | { kind: 'conflict'; names: string[] };

/** Names among `names` that already belong to an agent. */
export async function takenNames(db: D1Database, names: string[]): Promise<string[]> {
  const taken = await db.prepare(`SELECT name FROM api_keys WHERE name IN (${names.map(() => '?').join(', ')})`)
    .bind(...names).all<{ name: string }>();
  return taken.results.map(r => r.name);
}

export interface JoinContext { deviceId: string | null; invite: ConsumedInvite | null; bootstrap: boolean }

/** Rejects up front when any requested name already belongs to an agent. */
export async function createJoinRequest(db: D1Database, payload: JoinPayload, context: JoinContext): Promise<CreateOutcome> {
  const conflicts = await takenNames(db, payload.profiles.map(p => p.name));
  if (conflicts.length) return { kind: 'conflict', names: conflicts };
  const pollToken = `jt_${randomHex(24)}`;
  const { deviceId, invite, bootstrap } = context;
  const label = deviceId ? await deviceLabel(db, deviceId) ?? payload.device.label : payload.device.label;
  const code = bootstrap ? null : verificationCode();
  const row = await db.prepare(`INSERT INTO join_requests (poll_token_hash, device_label, device_host, device_id, profiles,
    invite_id, inviter_label, verification_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id`)
    .bind(await hashApiKey(pollToken), label, payload.device.host, deviceId, JSON.stringify(payload.profiles),
      invite?.id ?? null, invite?.inviterLabel ?? null, code)
    .first<{ id: string }>();
  if (!row) throw new Error('join request insert returned no row');
  const pending = { kind: 'created' as const, requestId: row.id, pollToken, status: 'pending' as const, verificationCode: code };
  if (!bootstrap) return pending;
  const approved = await approveJoin(db, row.id, { type: 'system', id: 'join' }, { firstOnly: true });
  if (!approved.ok) return pending;
  const delivered = await pollJoinRequest(db, pollToken);
  return { ...pending, status: 'approved', delivery: delivered?.delivery };
}

export interface PollResult {
  requestId: string;
  status: JoinRequestRow['status'];
  deviceLabel: string;
  verificationCode: string | null;
  profiles: Array<{ profile: string; name: string }>;
  delivery?: Delivery;
  delivered: boolean;
}

/** Reads and clears the delivery in one transaction, so keys leave the server once. */
export async function pollJoinRequest(db: D1Database, pollToken: string): Promise<PollResult | null> {
  const hash = await hashApiKey(pollToken);
  const [read] = await db.batch<JoinRequestRow>([
    db.prepare('SELECT * FROM join_requests WHERE poll_token_hash = ?').bind(hash),
    db.prepare(`UPDATE join_requests SET delivery = NULL, updated_at = datetime('now')
      WHERE poll_token_hash = ? AND status = 'approved' AND delivery IS NOT NULL`).bind(hash),
  ]);
  const row = read.results[0];
  if (!row) return null;
  const delivery = row.status === 'approved' && row.delivery ? parseDelivery(row.delivery) : undefined;
  return {
    requestId: row.id,
    status: row.status,
    deviceLabel: row.device_label,
    verificationCode: row.verification_code,
    profiles: parseStoredProfiles(row.profiles),
    delivery,
    delivered: row.status === 'approved' && !row.delivery,
  };
}

/** Maps an existing agent key to its device; null means the proof is invalid or deviceless. */
export async function resolveDeviceProof(db: D1Database, key: string): Promise<string | null> {
  const row = await db.prepare(`SELECT a.device_id FROM agent_keys k JOIN api_keys a ON a.id = k.agent_id
    WHERE k.key_hash = ? AND k.revoked_at IS NULL AND a.device_id IS NOT NULL`)
    .bind(await hashApiKey(key)).first<{ device_id: string }>();
  return row?.device_id ?? null;
}

async function deviceLabel(db: D1Database, deviceId: string): Promise<string | null> {
  return db.prepare('SELECT label FROM devices WHERE id = ?').bind(deviceId).first<string>('label');
}

function parseDelivery(json: string): Delivery | undefined {
  try {
    return JSON.parse(json) as Delivery;
  } catch {
    return undefined;
  }
}

function randomHex(bytes: number): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), b => b.toString(16).padStart(2, '0')).join('');
}
