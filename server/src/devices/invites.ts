// Single-use device invites minted by an enrolled agent, plus join verification codes.
// Exports deviceInvitesRouter (POST /api/devices/invites), consumeInvite, verificationCode.
// Depends on agent auth, D1 and SHA-256 hashing; an invite never skips boss approval.
import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId, hashApiKey } from '../middleware/auth';
import { logAudit } from '../audit';

const INVITE_TTL_MS = 30 * 60 * 1000;
const MAX_ACTIVE_INVITES = 5;

export interface ConsumedInvite { id: string; inviterLabel: string }

const router = new Hono<{ Bindings: Env }>({});
router.use('*', apiAuth);

router.post('/invites', async (c) => {
  const agentId = getAgentId(c);
  const now = new Date().toISOString();
  await c.env.DB.prepare('DELETE FROM device_invites WHERE inviter_agent_id = ? AND expires_at <= ?').bind(agentId, now).run();
  const active = await c.env.DB.prepare(`SELECT COUNT(*) AS n FROM device_invites
    WHERE inviter_agent_id = ? AND consumed_at IS NULL AND expires_at > ?`).bind(agentId, now).first<number>('n');
  if ((active ?? 0) >= MAX_ACTIVE_INVITES) return c.json({ error: 'too many active invites' }, 429);
  const label = await inviterLabel(c.env.DB, agentId);
  const invite = `hb_inv_${randomHex(32)}`;
  const expiresAt = new Date(Date.now() + INVITE_TTL_MS).toISOString();
  const row = await c.env.DB.prepare(`INSERT INTO device_invites (token_hash, inviter_agent_id, inviter_label, expires_at)
    VALUES (?, ?, ?, ?) RETURNING id`).bind(await hashApiKey(invite), agentId, label, expiresAt).first<{ id: string }>();
  if (!row) return c.json({ error: 'failed to create invite' }, 500);
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'device_invite.create', 'device_invite', row.id, label));
  return c.json({ invite, expires_at: expiresAt, inviter_label: label }, 201);
});

/** Atomically consumes an unexpired invite; null when it is unknown, used or expired. */
export async function consumeInvite(db: D1Database, invite: string): Promise<ConsumedInvite | null> {
  const row = await db.prepare(`UPDATE device_invites SET consumed_at = datetime('now')
    WHERE token_hash = ? AND consumed_at IS NULL AND expires_at > ? RETURNING id, inviter_label`)
    .bind(await hashApiKey(invite), new Date().toISOString()).first<{ id: string; inviter_label: string }>();
  return row ? { id: row.id, inviterLabel: row.inviter_label } : null;
}

/** Six uniformly random digits, shown on the joining machine and on the approval surface. */
export function verificationCode(): string {
  const limit = Math.floor(0x1_0000_0000 / 1_000_000) * 1_000_000;
  for (;;) {
    const [value] = crypto.getRandomValues(new Uint32Array(1));
    if (value < limit) return String(value % 1_000_000).padStart(6, '0');
  }
}

async function inviterLabel(db: D1Database, agentId: string): Promise<string> {
  const row = await db.prepare(`SELECT a.name, d.label FROM api_keys a LEFT JOIN devices d ON d.id = a.device_id WHERE a.id = ?`)
    .bind(agentId).first<{ name: string; label: string | null }>();
  return row?.label ?? row?.name ?? 'an enrolled agent';
}

function randomHex(bytes: number): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), b => b.toString(16).padStart(2, '0')).join('');
}

export const deviceInvitesRouter = router;
