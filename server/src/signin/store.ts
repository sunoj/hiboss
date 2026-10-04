// D1 storage for "Sign in with iPhone" requests: open, approve, reject, and the
// single-use completion that checks the 6-digit code and consumes the request.
// Exports the request lifecycle functions used by routes/signin.ts.

import { hashApiKey } from '../middleware/auth';
import { verificationCode } from '../devices/invites';

export const SIGNIN_TTL_MS = 10 * 60 * 1000;
export const MAX_CODE_ATTEMPTS = 5;
/** Open requests across the whole server; creation is unauthenticated, so this bounds the table. */
export const MAX_OPEN_REQUESTS = 200;
/** Open requests from one network, so one client cannot exhaust the server-wide cap alone. */
export const MAX_OPEN_PER_ORIGIN = 3;

export type SigninStatus = 'pending' | 'approved' | 'rejected' | 'completed' | 'expired';

export interface SigninView {
  request_id: string;
  device_label: string;
  origin: string | null;
  status: SigninStatus;
  created_at: string;
  expires_at: string;
}

interface SigninRow {
  id: string;
  device_label: string;
  origin: string | null;
  status: Exclude<SigninStatus, 'expired'>;
  boss_id: string | null;
  created_at: string;
  expires_at: string;
}

function randomHex(bytes: number): string {
  const buffer = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(buffer, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** The code is hashed with its request id, so a code hash is useless for any other request. */
function codeHash(requestId: string, code: string): Promise<string> {
  return hashApiKey(`signin:${requestId}:${code}`);
}

export function toView(row: SigninRow, now: string): SigninView {
  const open = row.status === 'pending' || row.status === 'approved';
  const status: SigninStatus = open && row.expires_at <= now ? 'expired' : row.status;
  const { id, device_label, origin, created_at, expires_at } = row;
  return { request_id: id, device_label, origin, status, created_at, expires_at };
}

/** Opens a request; null when too many requests are already open, overall or from `originKey`. */
export async function openRequest(db: D1Database, deviceLabel: string, origin: string | null, originKey: string | null):
  Promise<{ request_id: string; poll_token: string; expires_at: string } | null> {
  const now = new Date();
  const nowIso = now.toISOString();
  await db.prepare('DELETE FROM signin_requests WHERE expires_at <= ?').bind(nowIso).run();
  const id = randomHex(16);
  const pollToken = `st_${randomHex(32)}`;
  const expiresAt = new Date(now.getTime() + SIGNIN_TTL_MS).toISOString();
  const inserted = await db.prepare(
    `INSERT INTO signin_requests (id, poll_token_hash, device_label, origin, origin_key, created_at, expires_at)
     SELECT ?, ?, ?, ?, ?, ?, ?
     WHERE (SELECT COUNT(*) FROM signin_requests WHERE status IN ('pending', 'approved')) < ?
       AND (? IS NULL OR (SELECT COUNT(*) FROM signin_requests WHERE origin_key = ? AND status IN ('pending', 'approved')) < ?)`,
  ).bind(id, await hashApiKey(pollToken), deviceLabel, origin, originKey, nowIso, expiresAt,
    MAX_OPEN_REQUESTS, originKey, originKey, MAX_OPEN_PER_ORIGIN).run();
  if (!inserted.meta.changes) return null;
  return { request_id: id, poll_token: pollToken, expires_at: expiresAt };
}

export function findById(db: D1Database, id: string): Promise<SigninRow | null> {
  return db.prepare('SELECT id, device_label, origin, status, boss_id, created_at, expires_at FROM signin_requests WHERE id = ?')
    .bind(id).first<SigninRow>();
}

export async function findByPollToken(db: D1Database, pollToken: string): Promise<SigninRow | null> {
  return db.prepare('SELECT id, device_label, origin, status, boss_id, created_at, expires_at FROM signin_requests WHERE poll_token_hash = ?')
    .bind(await hashApiKey(pollToken)).first<SigninRow>();
}

/** Approves an open request for the approving boss and returns the code to display, or null. */
export async function approveRequest(db: D1Database, id: string, bossId: string, tokenId: string): Promise<string | null> {
  const code = verificationCode();
  const approved = await db.prepare(
    `UPDATE signin_requests SET status = 'approved', boss_id = ?, approved_by_token_id = ?, code_hash = ?
     WHERE id = ? AND status = 'pending' AND expires_at > ? RETURNING id`,
  ).bind(bossId, tokenId, await codeHash(id, code), id, new Date().toISOString()).first<{ id: string }>();
  return approved ? code : null;
}

/** Rejects a pending request, or one this boss approved; true when a row changed. */
export async function rejectRequest(db: D1Database, id: string, bossId: string): Promise<boolean> {
  const result = await db.prepare(
    `UPDATE signin_requests SET status = 'rejected', code_hash = NULL
     WHERE id = ? AND (status = 'pending' OR (status = 'approved' AND boss_id = ?))`,
  ).bind(id, bossId).run();
  return result.meta.changes > 0;
}

/**
 * Checks `code` and counts the attempt in one statement, so concurrent guesses cannot
 * outrun the limit: every SET expression sees the row as it was before this update. A
 * match completes the request only while the boss is unarchived and the approving token
 * unrevoked, and rejects it otherwise; the last allowed miss rejects it too. Returns the
 * boss id on success.
 */
export async function completeRequest(db: D1Database, row: SigninRow, code: string): Promise<string | null> {
  const hash = await codeHash(row.id, code);
  const updated = await db.prepare(
    `UPDATE signin_requests SET attempts = attempts + 1,
       status = CASE
         WHEN code_hash = ?1
           AND EXISTS (SELECT 1 FROM bosses b WHERE b.id = signin_requests.boss_id AND b.archived_at IS NULL)
           AND EXISTS (SELECT 1 FROM boss_tokens bt WHERE bt.id = signin_requests.approved_by_token_id AND bt.revoked_at IS NULL)
         THEN 'completed'
         WHEN code_hash = ?1 OR attempts + 1 >= ?2 THEN 'rejected'
         ELSE status END,
       code_hash = CASE WHEN code_hash = ?1 THEN NULL ELSE code_hash END
     WHERE id = ?3 AND status = 'approved' AND expires_at > ?4 AND attempts < ?2
     RETURNING status, boss_id`,
  ).bind(hash, MAX_CODE_ATTEMPTS, row.id, new Date().toISOString()).first<{ status: string; boss_id: string }>();
  return updated?.status === 'completed' ? updated.boss_id : null;
}

export async function recordIssuedToken(db: D1Database, id: string, tokenId: string): Promise<void> {
  await db.prepare('UPDATE signin_requests SET issued_token_id = ? WHERE id = ?').bind(tokenId, id).run();
}
