// Handles boss-authenticated QR code issuance and unauthenticated redemption.
// Exports bossPairingRouter and pairingRouter mounted by the worker entrypoint.
// Depends on Hono, boss auth, token issuance, and D1 pairing-code storage.

import { Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, hashApiKey } from '../middleware/auth';
import { issueBossToken } from '../boss-token';

const PAIRING_CODE_BYTES = 32;
const PAIRING_TTL_MS = 5 * 60 * 1000;
const MAX_ACTIVE_PAIRING_CODES = 5;
const MAX_PAIRING_CODES_PER_MINUTE = 5;
const MAX_DEVICE_LABEL_LENGTH = 100;

interface PairingRedeemRequest {
  code: string;
  deviceLabel: string;
}

interface BossIdentity {
  id: string;
  name: string;
  role: string;
}

export const bossPairingRouter = createBossPairingRouter();
export const pairingRouter = createPairingRouter();

function createBossPairingRouter(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>({});
  routes.use('*', bossAuth);
  routes.post('/', async (c) => {
    const bossId = getBossId(c);
    const now = new Date().toISOString();
    const active = await c.env.DB.prepare(
      'SELECT COUNT(*) AS count FROM boss_pairing_codes WHERE boss_id = ? AND consumed_at IS NULL AND expires_at > ?',
    ).bind(bossId, now).first<{ count: number }>();
    const recent = await c.env.DB.prepare(
      "SELECT COUNT(*) AS count FROM boss_pairing_codes WHERE boss_id = ? AND created_at > datetime('now', '-1 minute')",
    ).bind(bossId).first<{ count: number }>();
    if ((active?.count ?? 0) >= MAX_ACTIVE_PAIRING_CODES || (recent?.count ?? 0) >= MAX_PAIRING_CODES_PER_MINUTE) {
      return c.text('too many pairing codes', 429);
    }
    const bytes = new Uint8Array(PAIRING_CODE_BYTES);
    crypto.getRandomValues(bytes);
    const code = `hb_pair_${Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('')}`;
    const expiresAt = new Date(Date.now() + PAIRING_TTL_MS).toISOString();
    await c.env.DB.prepare(
      'INSERT INTO boss_pairing_codes (boss_id, code_hash, expires_at) VALUES (?, ?, ?)',
    ).bind(bossId, await hashApiKey(code), expiresAt).run();
    return c.json({ code, expires_at: expiresAt });
  });
  return routes;
}

function createPairingRouter(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>({});
  routes.post('/redeem', async (c) => {
    let body: unknown;
    try {
      body = await c.req.json<unknown>();
    } catch {
      return c.text('code and device_label are required', 400);
    }
    const request = parsePairingRedeemRequest(body);
    if (!request) return c.text('code and device_label are required', 400);
    const now = new Date().toISOString();
    const claimed = await c.env.DB.prepare(
      'UPDATE boss_pairing_codes SET consumed_at = ? WHERE code_hash = ? AND consumed_at IS NULL AND expires_at > ? RETURNING boss_id',
    ).bind(now, await hashApiKey(request.code), now).first<{ boss_id: string }>();
    if (!claimed) return c.text('invalid or expired pairing code', 400);
    const boss = await c.env.DB.prepare('SELECT id, name, role FROM bosses WHERE id = ?')
      .bind(claimed.boss_id).first<BossIdentity>();
    if (!boss) return c.text('invalid or expired pairing code', 400);
    const token = await issueBossToken(c.env, boss.id, request.deviceLabel);
    return c.json({ token, boss });
  });
  return routes;
}

function parsePairingRedeemRequest(value: unknown): PairingRedeemRequest | null {
  if (!value || typeof value !== 'object') return null;
  const record = value as Record<string, unknown>;
  const code = typeof record.code === 'string' ? record.code.trim() : '';
  const deviceLabel = typeof record.device_label === 'string' ? record.device_label.trim() : '';
  if (!code || !deviceLabel || deviceLabel.length > MAX_DEVICE_LABEL_LENGTH || /[<>&\u0000-\u001f]/.test(deviceLabel)) return null;
  return { code, deviceLabel };
}
