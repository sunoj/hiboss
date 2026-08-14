// Progress feed routes for agent posts and boss-readable project timelines.
// Exports progressRouter mounted at /api/progress.
// Depends on Hono, D1, dual authentication, and boss access control.

import { Context, Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, dualAuth, getAgentId, getBossId, getBossRole, isBossAuth } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api';
import {
  mapProgressRow,
  normalizeTimestamp,
  parseCreatePayload,
  progressSelect,
  verifyMediaOwnership,
  isRecord,
  type ProgressCursor,
  type ProgressRow,
} from './progress-helpers';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', dualAuth);

async function getScopeAgentIds(c: Context<{ Bindings: Env }>): Promise<string[]> {
  if (!isBossAuth(c)) return [getAgentId(c)];
  return getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
}

function scopedWhere(agentIds: string[]): { sql: string; binds: string[] } {
  const placeholders = agentIds.map(() => '?').join(', ');
  return { sql: `agent_id IN (${placeholders})`, binds: agentIds };
}

function parseLimit(value: string | undefined): number {
  const parsed = Number(value ?? DEFAULT_LIMIT);
  if (!Number.isInteger(parsed) || parsed <= 0) return DEFAULT_LIMIT;
  return Math.min(parsed, MAX_LIMIT);
}

function parseCursor(value: string | undefined): ProgressCursor | string | null {
  if (!value) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    return 'before must be a JSON cursor with created_at and id';
  }
  if (!isRecord(parsed) || typeof parsed.created_at !== 'string' || typeof parsed.id !== 'string' || !parsed.created_at || !parsed.id) {
    return 'before must be a JSON cursor with created_at and id';
  }
  return { created_at: parsed.created_at, id: parsed.id };
}

async function findProgressPost(env: Env, id: string, agentIds: string[], bossId: string | null): Promise<ProgressRow | null> {
  const scope = scopedWhere(agentIds);
  return env.DB.prepare(
    `${progressSelect()} WHERE p.id = ? AND p.${scope.sql}`
  ).bind(bossId, id, ...scope.binds).first<ProgressRow>();
}

routes.post('/', async (c) => {
  if (isBossAuth(c)) return c.text('agent authentication required', 403);
  const payload = await parseCreatePayload(c);
  if (typeof payload === 'string') return c.text(payload, 400);
  const agentId = getAgentId(c);
  const agent = await c.env.DB.prepare('SELECT name FROM api_keys WHERE id = ?').bind(agentId).first<{ name: string }>();
  if (!agent) return c.text('agent not found', 404);
  const project = payload.project ?? agent.name;
  const mediaError = await verifyMediaOwnership(c, payload.media ?? [], agentId);
  if (mediaError) return c.text(mediaError, 400);
  const row = await c.env.DB.prepare(
    `INSERT INTO progress_posts (agent_id, session_id, project, body, media, tags) VALUES (?, ?, ?, ?, ?, ?) RETURNING id`
  ).bind(agentId, payload.session_id, project, payload.body, payload.media ? JSON.stringify(payload.media) : null, payload.tags ? JSON.stringify(payload.tags) : null).first<{ id: string }>();
  if (!row) return c.text('failed to create post', 500);
  const post = await findProgressPost(c.env, row.id, [agentId], null);
  if (!post) return c.text('failed to load post', 500);
  return c.json(mapProgressRow(post, new URL(c.req.url), false), 201);
});

routes.get('/', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.json({ posts: [], next_cursor: null });
  const scope = scopedWhere(agentIds);
  const params = c.req.query();
  const cursor = parseCursor(params.before);
  if (typeof cursor === 'string') return c.text(cursor, 400);
  const clauses = [`p.${scope.sql}`];
  const binds: (string | number)[] = [...scope.binds];
  if (params.project) { clauses.push('p.project = ?'); binds.push(params.project); }
  if (isBossAuth(c) && params.agent_id) { clauses.push('p.agent_id = ?'); binds.push(params.agent_id); }
  if (cursor) {
    clauses.push('(p.created_at < datetime(?) OR (p.created_at = datetime(?) AND p.id < ?))');
    binds.push(cursor.created_at, cursor.created_at, cursor.id);
  }
  const limit = parseLimit(params.limit);
  binds.push(limit);
  const bossId = isBossAuth(c) ? getBossId(c) : null;
  const rows = await c.env.DB.prepare(
    `${progressSelect()} WHERE ${clauses.join(' AND ')} ORDER BY p.created_at DESC, p.id DESC LIMIT ?`
  ).bind(bossId, ...binds).all<ProgressRow>();
  const posts = (rows.results ?? []).map((row) => mapProgressRow(row, new URL(c.req.url), isBossAuth(c)));
  const lastRow = rows.results?.[rows.results.length - 1];
  const nextCursor = posts.length === limit && lastRow
    ? { created_at: normalizeTimestamp(lastRow.created_at), id: lastRow.id }
    : null;
  return c.json({ posts, next_cursor: nextCursor });
});

routes.get('/projects', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.json({ projects: [] });
  const scope = scopedWhere(agentIds);
  const rows = await c.env.DB.prepare(
    `SELECT p.project, COUNT(*) AS count, MAX(p.created_at) AS last_post_at, p.agent_id FROM progress_posts p WHERE p.${scope.sql} GROUP BY p.project, p.agent_id ORDER BY last_post_at DESC`
  ).bind(...scope.binds).all<{ project: string; count: number; last_post_at: string; agent_id: string }>();
  return c.json({ projects: (rows.results ?? []).map((row) => ({ ...row, last_post_at: normalizeTimestamp(row.last_post_at) })) });
});

async function likePost(c: Context<{ Bindings: Env }>, like: boolean): Promise<Response> {
  const bossId = getBossId(c);
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.text('not found', 404);
  const id = c.req.param('id');
  if (!id) return c.text('not found', 404);
  const post = await findProgressPost(c.env, id, agentIds, bossId);
  if (!post) return c.text('not found', 404);
  if (like) {
    await c.env.DB.prepare('INSERT OR IGNORE INTO progress_likes (post_id, boss_id) VALUES (?, ?)').bind(post.id, bossId).run();
  } else {
    await c.env.DB.prepare('DELETE FROM progress_likes WHERE post_id = ? AND boss_id = ?').bind(post.id, bossId).run();
  }
  const count = await c.env.DB.prepare('SELECT COUNT(*) AS count FROM progress_likes WHERE post_id = ?').bind(post.id).first<{ count: number }>();
  return c.json({ like_count: count?.count ?? 0, liked: like });
}

routes.post('/:id/like', bossAuth, (c) => likePost(c, true));
routes.delete('/:id/like', bossAuth, (c) => likePost(c, false));

routes.get('/:id', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.text('not found', 404);
  const bossId = isBossAuth(c) ? getBossId(c) : null;
  const id = c.req.param('id');
  if (!id) return c.text('not found', 404);
  const post = await findProgressPost(c.env, id, agentIds, bossId);
  return post ? c.json(mapProgressRow(post, new URL(c.req.url), isBossAuth(c))) : c.text('not found', 404);
});

routes.delete('/:id', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.text('not found', 404);
  const scope = scopedWhere(agentIds);
  const result = await c.env.DB.prepare(`DELETE FROM progress_posts WHERE id = ? AND ${scope.sql}`).bind(c.req.param('id'), ...scope.binds).run();
  return result.meta.changes ? c.body(null, 204) : c.text('not found', 404);
});

export const progressRouter = routes;
