// Parses shared Box list/search filters and stable pagination cursors.
// All generated SQL includes owner scope and excludes soft-deleted rows.
import { HTTPException } from 'hono/http-exception';
import { KINDS, type BoxContext, type BoxCursor, type BoxFilter } from './types';
import { boxBossIds } from './access';

function cursor(value: string | undefined): BoxCursor | null {
  if (value === undefined) return null;
  try {
    if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('invalid base64url');
    const json = atob(value.replaceAll('-', '+').replaceAll('_', '/'));
    if (btoa(json).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '') !== value) {
      throw new Error('invalid base64url');
    }
    const parsed: unknown = JSON.parse(json);
    if (parsed && typeof parsed === 'object' && 'created_at' in parsed && 'id' in parsed
      && typeof parsed.created_at === 'string' && typeof parsed.id === 'string'
      && Number.isFinite(Date.parse(parsed.created_at)) && parsed.id
      && (!('score' in parsed) || (typeof parsed.score === 'number' && Number.isFinite(parsed.score)))) {
      return parsed as BoxCursor;
    }
  } catch { /* Invalid cursors are rejected below. */ }
  throw new HTTPException(400, { message: 'invalid cursor' });
}

function since(value: string): string {
  const relative = /^(\d+)(s|m|h|d)$/.exec(value);
  const units: Record<string, number> = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
  const time = relative ? Date.now() - Number(relative[1]) * units[relative[2]] : Date.parse(value);
  if (!Number.isFinite(time) || Math.abs(time) > 8.64e15) {
    throw new HTTPException(400, { message: 'invalid since' });
  }
  return new Date(time).toISOString();
}

export async function boxFilter(c: BoxContext): Promise<BoxFilter> {
  const bosses = await boxBossIds(c);
  if (!bosses.length) throw new HTTPException(404, { message: 'not found' });
  const params = c.req.query();
  const clauses = [`i.boss_id IN (${bosses.map(() => '?').join(',')})`, 'i.deleted_at IS NULL'];
  const binds: (string | number)[] = [...bosses];
  if (params.boss) {
    const owner = await c.env.DB.prepare(`SELECT id FROM bosses WHERE id IN
      (${bosses.map(() => '?').join(',')}) AND (id = ? OR name = ?) LIMIT 1`)
      .bind(...bosses, params.boss, params.boss).first<{ id: string }>();
    if (!owner) throw new HTTPException(404, { message: 'not found' });
    clauses.push('i.boss_id = ?');
    binds.push(owner.id);
  }
  if (params.kind) {
    if (!KINDS.some(kind => kind === params.kind)) throw new HTTPException(400, { message: 'invalid kind' });
    clauses.push('i.kind = ?');
    binds.push(params.kind);
  }
  if (params.project) { clauses.push('i.project = ?'); binds.push(params.project); }
  if (params.since) { clauses.push('i.created_at >= ?'); binds.push(since(params.since)); }
  const requested = Number(params.limit ?? 20);
  if (!Number.isInteger(requested) || requested <= 0) {
    throw new HTTPException(400, { message: 'invalid limit' });
  }
  return { sql: clauses.join(' AND '), binds, limit: Math.min(requested, 100),
    cursor: cursor(params.cursor) };
}

export function recencyCursor(filter: BoxFilter): void {
  if (!filter.cursor) return;
  filter.sql += ' AND (i.created_at < ? OR (i.created_at = ? AND i.id < ?))';
  filter.binds.push(filter.cursor.created_at, filter.cursor.created_at, filter.cursor.id);
}
