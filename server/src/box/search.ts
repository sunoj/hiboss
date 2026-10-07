// Scoped recency lists and ranked FTS5 search for live Box items.
// Exports read handlers with shared filters and stable JSON pagination cursors.
import { HTTPException } from 'hono/http-exception';
import { boxFilter, recencyCursor } from './filters';
import { BOX_SELECT } from './store';
import { itemResponse, type BoxContext, type BoxCursor, type BoxRow } from './types';

type RankedRow = BoxRow & { score: number };

function respond(c: BoxContext, rows: (BoxRow & { score?: number })[], limit: number): Response {
  const visible = rows.slice(0, limit);
  const last = visible.at(-1);
  const cursor: BoxCursor | null = rows.length > limit && last
    ? { created_at: last.created_at, id: last.id, ...('score' in last ? { score: last.score } : {}) }
    : null;
  return c.json({ items: visible.map(row => {
    const { score, ...item } = row;
    return itemResponse(item);
  }), next_cursor: cursor === null ? null
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
  const query = c.req.query('q')?.trim();
  if (!query) throw new HTTPException(400, { message: 'q is required' });
  const match = query.split(/\s+/).map(term => `"${term.replaceAll('"', '""')}"`).join(' AND ');
  let after = '';
  if (filter.cursor) {
    if (filter.cursor.score === undefined) {
      throw new HTTPException(400, { message: 'search cursor needs score' });
    }
    after = `WHERE (score > ? OR (score = ? AND (created_at < ? OR (created_at = ? AND id < ?))))`;
  }
  const binds: (string | number)[] = [match, ...filter.binds];
  if (filter.cursor) {
    const { score, created_at, id } = filter.cursor;
    binds.push(score as number, score as number, created_at, created_at, id);
  }
  const rows = await c.env.DB.prepare(`WITH matches AS MATERIALIZED (
    SELECT i.*, b.name AS boss_name, bm25(box_items_fts) AS score
    FROM box_items_fts JOIN box_items i ON i.rowid = box_items_fts.rowid
    JOIN bosses b ON b.id = i.boss_id WHERE box_items_fts MATCH ? AND ${filter.sql}
    ) SELECT * FROM matches ${after} ORDER BY score, created_at DESC, id DESC LIMIT ?`)
    .bind(...binds, filter.limit + 1).all<RankedRow>();
  return respond(c, rows.results, filter.limit);
}
