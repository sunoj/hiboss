// Discovers pending input independently of a panel's wall visibility preferences.
// Exports a scoped, paginated summary query with no form contents or accepted answers.
// Dependencies: D1, strict cursor parsing, and the panel fault contract.

import { panelTargetAccessSql } from '../access';
import { isRecord } from '../definition/helpers';
import { PanelFault } from '../lifecycle/types';

interface Cursor { createdAt: string; requestId: string }
interface PendingRow {
  request_id: string; panel_id: string; revision: number; title: string;
  blocking: number; expires_at: string | null; created_at: string;
}
interface PendingPage {
  requests: Array<{ requestId: string; panelId: string; requestRevision: number; title: string;
    blocking: boolean; expiresAt: string | null; createdAt: string }>;
  nextCursor: string | null;
}
function cursorValue(raw?: string): Cursor | null {
  if (!raw) return null;
  try {
    if (raw.length > 512) throw new Error();
    const value: unknown = JSON.parse(atob(raw.replaceAll('-', '+').replaceAll('_', '/')));
    if (!isRecord(value) || Object.keys(value).length !== 2 || typeof value.createdAt !== 'string'
      || !Number.isFinite(Date.parse(value.createdAt)) || typeof value.requestId !== 'string'
      || !/^[A-Za-z0-9_-]{1,128}$/.test(value.requestId)) throw new Error();
    return { createdAt: value.createdAt, requestId: value.requestId };
  } catch { throw new PanelFault('invalid_cursor', 400); }
}
export async function pendingRequests(db: D1Database, identity: string, role: 'producer' | 'subscriber', rawCursor?: string, rawLimit?: string): Promise<PendingPage> {
  const limit = rawLimit === undefined ? 50 : Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new PanelFault('invalid_limit', 400);
  const cursor = cursorValue(rawCursor);
  const scope = role === 'producer' ? 'p.agent_id = ?' : 'p.target_boss_id = ?';
  const after = cursor ? 'AND (r.created_at > ? OR (r.created_at = ? AND r.request_id > ?))' : '';
  const binds: Array<string | number> = [identity, new Date().toISOString()];
  if (cursor) binds.push(cursor.createdAt, cursor.createdAt, cursor.requestId);
  binds.push(limit + 1);
  const result = await db.prepare(`SELECT r.request_id, r.panel_id, r.revision, r.blocking, r.expires_at, r.created_at,
      json_extract(d.definition_json, '$.title') AS title
    FROM interaction_requests r JOIN panels p ON p.panel_id = r.panel_id
    JOIN interaction_revisions d ON d.request_id = r.request_id AND d.revision = r.revision
    WHERE ${panelTargetAccessSql('p')} AND ${scope} AND r.state = 'open' AND (r.expires_at IS NULL OR r.expires_at > ?)
      AND json_extract(p.lifecycle_json, '$.taskState') IN ('running', 'paused') ${after}
    ORDER BY r.created_at, r.request_id LIMIT ?`).bind(...binds).all<PendingRow>();
  const rows = result.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor = result.results.length > limit && last
    ? btoa(JSON.stringify({ createdAt: last.created_at, requestId: last.request_id })).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '') : null;
  return { requests: rows.map(row => ({ requestId: row.request_id, panelId: row.panel_id, requestRevision: row.revision,
    title: row.title, blocking: row.blocking === 1, expiresAt: row.expires_at, createdAt: row.created_at })), nextCursor };
}
