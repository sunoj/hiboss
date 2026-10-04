// D1 storage for "Sign in with iPhone" requests: open, approve, reject, and the
// single-use completion that checks the 6-digit code and consumes the request.
// Exports the request lifecycle functions used by routes/signin.ts.

import { hashApiKey } from '../middleware/auth';
import { verificationCode } from '../devices/invites';

export const SIGNIN_TTL_MS = 10 * 60 * 1000;
export const MAX_CODE_ATTEMPTS = 5;
/** Open requests across the whole server; creation is unauthenticated, so this bounds the table. */
export const MAX_OPEN_REQUESTS = 200;

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

/** Opens a request; null when too many requests are already open. */
export async function openRequest(db: D1Database, deviceLabel: string, origin: string | null):
  Promise<{ request_id: string; poll_token: string; expires_at: string } | null> {
  const now = new Date();
  const nowIso = now.toISOString();
  await db.prepare('DELETE FROM signin_requests WHERE expires_at <= ?').bind(nowIso).run();
  const id = randomHex(16);
  const pollToken = `st_${randomHex(32)}`;
  const expiresAt = new Date(now.getTime() + SIGNIN_TTL_MS).toISOString();
  const inserted = await db.prepare(
    `INSERT INTO signin_requests (id, poll_token_hash, device_label, origin, created_at, expires_at)
     SELECT ?, ?, ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM signin_requests WHERE status IN ('pending', 'approved')) < ?`,
  ).bind(id, await hashApiKey(pollToken), deviceLabel, origin, nowIso, expiresAt, MAX_OPEN_REQUESTS).run();
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
 * Consumes an approved request when `code` matches, in one statement: the request must be
 * unexpired, under the attempt limit, its boss unarchived and its approving token unrevoked.
 * A wrong code counts an attempt; the last allowed miss rejects the request.
 */
export async function completeRequest(db: D1Database, row: SigninRow, code: string): Promise<string | null> {
  const consumed = await db.prepare(
    `UPDATE signin_requests SET status = 'completed', code_hash = NULL
     WHERE id = ? AND status = 'approved' AND expires_at > ? AND attempts < ? AND code_hash = ?
       AND EXISTS (SELECT 1 FROM bosses b WHERE b.id = signin_requests.boss_id AND b.archived_at IS NULL)
       AND EXISTS (SELECT 1 FROM boss_tokens bt WHERE bt.id = signin_requests.approved_by_token_id AND bt.revoked_at IS NULL)
     RETURNING boss_id`,
  ).bind(row.id, new Date().toISOString(), MAX_CODE_ATTEMPTS, await codeHash(row.id, code)).first<{ boss_id: string }>();
  if (consumed) return consumed.boss_id;
  await db.prepare(
    `UPDATE signin_requests SET attempts = attempts + 1,
       status = CASE WHEN attempts + 1 >= ? THEN 'rejected' ELSE status END
     WHERE id = ? AND status = 'approved'`,
  ).bind(MAX_CODE_ATTEMPTS, row.id).run();
  return null;
}

export async function recordIssuedToken(db: D1Database, id: string, tokenId: string): Promise<void> {
  await db.prepare('UPDATE signin_requests SET issued_token_id = ? WHERE id = ?').bind(tokenId, id).run();
}
