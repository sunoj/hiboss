// Progress feed routes for agent posts and boss-readable project timelines.
// Exports progressRouter mounted at /api/progress.
// Depends on Hono, D1, dual authentication, and boss access control.

import { Context, Hono } from 'hono';
import type { Env } from '../types';
import { dualAuth, getAgentId, getBossId, getBossRole, isBossAuth } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;
const MAX_BODY_LENGTH = 2000;

type MediaKind = 'image' | 'video';
interface MediaItem {
  url: string;
  kind: MediaKind;
  content_type: string;
  size: number;
  width?: number;
  height?: number;
  duration_ms?: number;
  poster_url?: string;
  alt?: string;
}
interface ProgressPost {
  id: string;
  project: string;
  agent_id: string;
  agent_name: string;
  session_id: string | null;
  body: string;
  media: MediaItem[];
  tags: string[];
  created_at: string;
}
interface ProgressRow {
  id: string;
  agent_id: string;
  agent_name: string;
  session_id: string | null;
  project: string;
  body: string;
  media: string | null;
  tags: string | null;
  created_at: string;
}
interface CreatePayload {
  body: string;
  project: string | null;
  session_id: string | null;
  media: MediaItem[] | null;
  tags: string[] | null;
}

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', dualAuth);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

function isAttachmentUrl(value: string, requestUrl: URL): boolean {
  try {
    const url = new URL(value);
    return url.origin === requestUrl.origin && /^\/api\/attachments\/[^/]+$/.test(url.pathname);
  } catch {
    return false;
  }
}

function parseMediaItem(value: unknown, requestUrl: URL): MediaItem | string {
  if (!isRecord(value)) return 'media items must be objects';
  if (typeof value.url !== 'string' || !isAttachmentUrl(value.url, requestUrl)) {
    return 'media URLs must point to this worker attachments path';
  }
  if (value.kind !== 'image' && value.kind !== 'video') return 'media kind must be image or video';
  if (typeof value.content_type !== 'string' || !value.content_type) return 'media content_type is required';
  if (!isNonNegativeInteger(value.size)) return 'media size must be a non-negative integer';
  for (const field of ['width', 'height', 'duration_ms']) {
    if (value[field] !== undefined && !isNonNegativeInteger(value[field])) return `media ${field} must be a non-negative integer`;
  }
  if (value.poster_url !== undefined && (typeof value.poster_url !== 'string' || !isAttachmentUrl(value.poster_url, requestUrl))) {
    return 'poster URLs must point to this worker attachments path';
  }
  if (value.alt !== undefined && typeof value.alt !== 'string') return 'media alt must be a string';
  return value as unknown as MediaItem;
}

async function parseCreatePayload(c: Context<{ Bindings: Env }>): Promise<CreatePayload | string> {
  let input: unknown;
  try {
    input = await c.req.json<unknown>();
  } catch {
    return 'invalid JSON body';
  }
  if (!isRecord(input) || typeof input.body !== 'string') return 'body is required';
  if (!input.body.trim()) return 'body must not be empty';
  if (input.body.length > MAX_BODY_LENGTH) return 'body is too long (max 2000 characters)';
  const project = input.project === undefined ? null : input.project;
  if (project !== null && (typeof project !== 'string' || !project.trim())) return 'project must be a non-empty string';
  const sessionId = input.session_id === undefined || input.session_id === null ? null : input.session_id;
  if (sessionId !== null && typeof sessionId !== 'string') return 'session_id must be a string';
  const requestUrl = new URL(c.req.url);
  const mediaInput = input.media === undefined || input.media === null ? [] : input.media;
  if (!Array.isArray(mediaInput) || mediaInput.length > 4) return 'media must contain at most 4 items';
  const media: MediaItem[] = [];
  for (const item of mediaInput) {
    const parsed = parseMediaItem(item, requestUrl);
    if (typeof parsed === 'string') return parsed;
    media.push(parsed);
  }
  const tagsInput = input.tags === undefined || input.tags === null ? [] : input.tags;
  if (!Array.isArray(tagsInput) || tagsInput.length > 8 || tagsInput.some((tag) => typeof tag !== 'string')) {
    return 'tags must contain at most 8 strings';
  }
  return { body: input.body, project: project as string | null, session_id: sessionId, media: media.length ? media : null, tags: tagsInput.length ? tagsInput as string[] : null };
}

function normalizeTimestamp(value: string): string {
  const iso = value.includes('T') ? value : value.replace(' ', 'T');
  return iso.endsWith('Z') ? iso : `${iso}Z`;
}

function parseArray<T>(value: string | null): T[] {
  if (!value) return [];
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed as T[] : [];
  } catch {
    return [];
  }
}

function mapProgressRow(row: ProgressRow): ProgressPost {
  return {
    id: row.id,
    project: row.project,
    agent_id: row.agent_id,
    agent_name: row.agent_name,
    session_id: row.session_id,
    body: row.body,
    media: parseArray<MediaItem>(row.media),
    tags: parseArray<string>(row.tags),
    created_at: normalizeTimestamp(row.created_at),
  };
}

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

async function findProgressPost(env: Env, id: string, agentIds: string[]): Promise<ProgressRow | null> {
  const scope = scopedWhere(agentIds);
  return env.DB.prepare(
    `SELECT p.*, a.name AS agent_name FROM progress_posts p JOIN api_keys a ON a.id = p.agent_id WHERE p.id = ? AND p.${scope.sql}`
  ).bind(id, ...scope.binds).first<ProgressRow>();
}

routes.post('/', async (c) => {
  if (isBossAuth(c)) return c.text('agent authentication required', 403);
  const payload = await parseCreatePayload(c);
  if (typeof payload === 'string') return c.text(payload, 400);
  const agentId = getAgentId(c);
  const agent = await c.env.DB.prepare('SELECT name FROM api_keys WHERE id = ?').bind(agentId).first<{ name: string }>();
  if (!agent) return c.text('agent not found', 404);
  const project = payload.project ?? agent.name;
  const row = await c.env.DB.prepare(
    `INSERT INTO progress_posts (agent_id, session_id, project, body, media, tags) VALUES (?, ?, ?, ?, ?, ?) RETURNING id`
  ).bind(agentId, payload.session_id, project, payload.body, payload.media ? JSON.stringify(payload.media) : null, payload.tags ? JSON.stringify(payload.tags) : null).first<{ id: string }>();
  if (!row) return c.text('failed to create post', 500);
  const post = await findProgressPost(c.env, row.id, [agentId]);
  if (!post) return c.text('failed to load post', 500);
  return c.json(mapProgressRow(post), 201);
});

routes.get('/', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.json({ posts: [], next_before: null });
  const scope = scopedWhere(agentIds);
  const params = c.req.query();
  const clauses = [`p.${scope.sql}`];
  const binds: (string | number)[] = [...scope.binds];
  if (params.project) { clauses.push('p.project = ?'); binds.push(params.project); }
  if (isBossAuth(c) && params.agent_id) { clauses.push('p.agent_id = ?'); binds.push(params.agent_id); }
  if (params.before) { clauses.push('p.created_at < datetime(?)'); binds.push(params.before); }
  const limit = parseLimit(params.limit);
  binds.push(limit);
  const rows = await c.env.DB.prepare(
    `SELECT p.*, a.name AS agent_name FROM progress_posts p JOIN api_keys a ON a.id = p.agent_id WHERE ${clauses.join(' AND ')} ORDER BY p.created_at DESC LIMIT ?`
  ).bind(...binds).all<ProgressRow>();
  const posts = (rows.results ?? []).map(mapProgressRow);
  const nextBefore = posts.length === limit ? posts[posts.length - 1]?.created_at ?? null : null;
  return c.json({ posts, next_before: nextBefore });
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

routes.get('/:id', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.text('not found', 404);
  const post = await findProgressPost(c.env, c.req.param('id'), agentIds);
  return post ? c.json(mapProgressRow(post)) : c.text('not found', 404);
});

routes.delete('/:id', async (c) => {
  const agentIds = await getScopeAgentIds(c);
  if (!agentIds.length) return c.text('not found', 404);
  const scope = scopedWhere(agentIds);
  const result = await c.env.DB.prepare(`DELETE FROM progress_posts WHERE id = ? AND ${scope.sql}`).bind(c.req.param('id'), ...scope.binds).run();
  return result.meta.changes ? c.body(null, 204) : c.text('not found', 404);
});

export const progressRouter = routes;
