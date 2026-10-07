// Scoped recency lists and FTS5 search for live Box items.
// Exports read handlers with shared filters and stable JSON pagination cursors.
import { HTTPException } from 'hono/http-exception';
import { boxFilter, recencyCursor } from './filters';
import { BOX_SELECT } from './store';
import { itemResponse, type BoxContext, type BoxCursor, type BoxRow } from './types';

function respond(c: BoxContext, rows: BoxRow[], limit: number): Response {
  const visible = rows.slice(0, limit);
  const last = visible.at(-1);
  const cursor: BoxCursor | null = rows.length > limit && last
    ? { created_at: last.created_at, id: last.id }
    : null;
  return c.json({ items: visible.map(itemResponse), next_cursor: cursor === null ? null
    : btoa(JSON.stringify(cursor)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '') });
}

export async function boxList(c: BoxContext): Promise<Response> {
  const filter = await boxFilter(c);
  recencyCursor(filter);
  const rows = await c.env.DB.prepare(`${BOX_SELECT} WHERE ${filter.sql}
    ORDER BY i.created_at DESC, i.id DESC LIMIT ?`)
    .bind(...filter.binds, filter.limit + 1).all<BoxRow>();
  return respond(c, rows.results, filter.limit);
}

export async function boxLatest(c: BoxContext): Promise<Response> {
  const filter = await boxFilter(c);
  const row = await c.env.DB.prepare(`${BOX_SELECT} WHERE ${filter.sql}
    ORDER BY i.created_at DESC, i.id DESC LIMIT 1`).bind(...filter.binds).first<BoxRow>();
  return row ? c.json(itemResponse(row)) : c.text('not found', 404);
}

export async function boxSearch(c: BoxContext): Promise<Response> {
  const filter = await boxFilter(c);
  recencyCursor(filter);
  const query = c.req.query('q')?.trim();
  if (!query) throw new HTTPException(400, { message: 'q is required' });
  if (query.includes('\0')) throw new HTTPException(400, { message: 'invalid q' });
  const match = query.split(/\s+/).map(term => `"${term.replaceAll('"', '""')}"`).join(' AND ');
  const rows = await c.env.DB.prepare(`${BOX_SELECT}
    JOIN box_items_fts ON i.rowid = box_items_fts.rowid WHERE box_items_fts MATCH ? AND ${filter.sql}
    ORDER BY i.created_at DESC, i.id DESC LIMIT ?`)
    .bind(match, ...filter.binds, filter.limit + 1).all<BoxRow>();
  return respond(c, rows.results, filter.limit);
}
