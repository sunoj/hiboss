// Team profile, generated avatar, and visible-team routes for the progress feed.
// Exports progressTeamsRouter mounted at /api/progress/teams.
// Depends on Hono, D1/R2, and shared progress identity helpers.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, dualAuth, getAgentId, getBossId, getBossRole, isBossAuth } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api';
import {
  getAttachmentKey,
  isRecord,
  mapTeamRow,
  slugifyProject,
  type TeamProfile,
  type TeamRow,
} from './progress-helpers';

const HANDLE_PATTERN = /^[a-z0-9_-]{1,32}$/;
const IDENTICON_PALETTE = ['#0f172a', '#0f766e', '#7c3aed', '#b45309', '#be123c', '#0369a1'];

interface TeamInput {
  handle?: string;
  display_name?: string;
  bio?: string | null;
  avatar_url?: string | null;
}

interface StoredTeam extends TeamRow {
  id: string;
  created_by_agent_id: string | null;
}

const routes = new Hono<{ Bindings: Env }>({});

function parseTeamInput(value: unknown): TeamInput | string {
  if (!isRecord(value)) return 'request body must be an object';
  const input: TeamInput = {};
  if (value.handle !== undefined) {
    if (typeof value.handle !== 'string' || !HANDLE_PATTERN.test(value.handle)) return 'handle must match [a-z0-9_-]{1,32}';
    input.handle = value.handle;
  }
  if (value.display_name !== undefined) {
    if (typeof value.display_name !== 'string' || !value.display_name.trim()) return 'display_name must be a non-empty string';
    input.display_name = value.display_name.trim();
  }
  if (value.bio !== undefined && value.bio !== null && typeof value.bio !== 'string') return 'bio must be a string or null';
  if (value.bio !== undefined) input.bio = value.bio as string | null;
  if (value.avatar_url !== undefined && value.avatar_url !== null && typeof value.avatar_url !== 'string') return 'avatar_url must be a string or null';
  if (value.avatar_url !== undefined) input.avatar_url = value.avatar_url as string | null;
  return input;
}

async function readTeam(env: Env, project: string): Promise<StoredTeam | null> {
  return env.DB.prepare('SELECT id, project, handle, display_name, bio, avatar_url, created_by_agent_id FROM progress_teams WHERE project = ?')
    .bind(project).first<StoredTeam>();
}

async function validateAvatar(env: Env, avatarUrl: string | null, requestUrl: URL, agentId: string): Promise<string | null> {
  if (avatarUrl === null) return null;
  const key = getAttachmentKey(avatarUrl, requestUrl);
  if (!key) return 'avatar_url must point to this worker attachments path';
  const object = await env.ATTACHMENTS.head(key);
  return object?.customMetadata?.agent_id === agentId ? null : 'avatar attachment does not exist or belongs to another agent';
}

async function hasHandleConflict(env: Env, handle: string, project: string): Promise<boolean> {
  const row = await env.DB.prepare('SELECT project FROM progress_teams WHERE handle = ? AND project != ?').bind(handle, project).first<{ project: string }>();
  return !!row;
}

async function saveTeam(env: Env, project: string, input: TeamInput, agentId: string): Promise<StoredTeam | null> {
  const existing = await readTeam(env, project);
  const handle = input.handle ?? existing?.handle ?? slugifyProject(project);
  const displayName = input.display_name ?? existing?.display_name ?? project;
  const bio = input.bio === undefined ? existing?.bio ?? null : input.bio;
  const avatarUrl = input.avatar_url === undefined ? existing?.avatar_url ?? null : input.avatar_url;
  if (await hasHandleConflict(env, handle, project)) return null;
  if (existing) {
    await env.DB.prepare("UPDATE progress_teams SET handle = ?, display_name = ?, bio = ?, avatar_url = ?, updated_at = datetime('now') WHERE project = ?")
      .bind(handle, displayName, bio, avatarUrl, project).run();
  } else {
    await env.DB.prepare('INSERT INTO progress_teams (project, handle, display_name, bio, avatar_url, created_by_agent_id) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(project, handle, displayName, bio, avatarUrl, agentId).run();
  }
  return readTeam(env, project);
}

async function renderIdenticon(handle: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(handle));
  const hash = new Uint8Array(digest);
  const background = IDENTICON_PALETTE[hash[0] % IDENTICON_PALETTE.length];
  let foregroundIndex = hash[1] % IDENTICON_PALETTE.length;
  if (IDENTICON_PALETTE[foregroundIndex] === background) foregroundIndex = (foregroundIndex + 1) % IDENTICON_PALETTE.length;
  const foreground = IDENTICON_PALETTE[foregroundIndex];
  const cells: string[] = [];
  for (let row = 0; row < 5; row++) {
    for (let column = 0; column < 3; column++) {
      const enabled = (hash[2 + row * 3 + column] & 1) === 1;
      if (!enabled) continue;
      cells.push(`<rect x="${20 + column * 12}" y="${20 + row * 12}" width="12" height="12"/>`);
      if (column < 2) cells.push(`<rect x="${20 + (4 - column) * 12}" y="${20 + row * 12}" width="12" height="12"/>`);
    }
  }
  const accentX = 26 + (hash[20] % 4) * 12;
  const accentY = 26 + (hash[21] % 4) * 12;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="24" fill="${background}"/><g fill="${foreground}">${cells.join('')}</g><circle cx="${accentX}" cy="${accentY}" r="4" fill="#fff" fill-opacity=".72"/></svg>`;
}

routes.get('/:handle/avatar.svg', async (c) => {
  const handle = c.req.param('handle');
  if (!handle) return c.text('not found', 404);
  const svg = await renderIdenticon(handle);
  return new Response(svg, { headers: { 'content-type': 'image/svg+xml', 'cache-control': 'public, max-age=31536000, immutable' } });
});

routes.put('/:project', apiAuth, async (c) => {
  const project = c.req.param('project');
  if (!project) return c.text('project is required', 400);
  let body: unknown;
  try { body = await c.req.json<unknown>(); } catch { return c.text('invalid JSON body', 400); }
  const input = parseTeamInput(body);
  if (typeof input === 'string') return c.text(input, 400);
  const agentId = getAgentId(c);
  const avatarError = await validateAvatar(c.env, input.avatar_url ?? null, new URL(c.req.url), agentId);
  if (avatarError) return c.text(avatarError, 400);
  try {
    const team = await saveTeam(c.env, project, input, agentId);
    if (!team) return c.text('handle is already in use', 409);
    return c.json(mapTeamRow(team, new URL(c.req.url)));
  } catch (error) {
    if (error instanceof Error && error.message.toLowerCase().includes('unique')) return c.text('handle is already in use', 409);
    throw error;
  }
});

routes.get('/', dualAuth, async (c) => {
  const agentIds = isBossAuth(c) ? await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c)) : [getAgentId(c)];
  if (!agentIds.length) return c.json({ teams: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await c.env.DB.prepare(
    `SELECT DISTINCT p.project, t.handle, t.display_name, t.bio, t.avatar_url FROM progress_posts p LEFT JOIN progress_teams t ON t.project = p.project WHERE p.agent_id IN (${placeholders}) ORDER BY p.project`
  ).bind(...agentIds).all<TeamRow>();
  const requestUrl = new URL(c.req.url);
  return c.json({ teams: (rows.results ?? []).map((row) => mapTeamRow(row, requestUrl)) });
});

export const progressTeamsRouter = routes;
