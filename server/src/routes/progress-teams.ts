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
const IDENTICON_SIZE = 64;
const SOURCE_SIZE = 100;
const PNG_SIGNATURE = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10]);

type Rgb = readonly [number, number, number];
type PngBytes = Uint8Array<ArrayBuffer>;

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

function parseColor(value: string): Rgb {
  return [Number.parseInt(value.slice(1, 3), 16), Number.parseInt(value.slice(3, 5), 16), Number.parseInt(value.slice(5, 7), 16)];
}

function isInsideRoundedBackground(x: number, y: number): boolean {
  const nearestX = Math.max(24, Math.min(76, x));
  const nearestY = Math.max(24, Math.min(76, y));
  return (x - nearestX) ** 2 + (y - nearestY) ** 2 <= 24 ** 2;
}

function isInsideMark(x: number, y: number, hash: Uint8Array): boolean {
  for (let row = 0; row < 5; row++) {
    for (let column = 0; column < 3; column++) {
      if ((hash[2 + row * 3 + column] & 1) === 0) continue;
      const cellY = 20 + row * 12;
      const cellX = 20 + column * 12;
      if (x >= cellX && x < cellX + 12 && y >= cellY && y < cellY + 12) return true;
      if (column < 2) {
        const mirrorX = 20 + (4 - column) * 12;
        if (x >= mirrorX && x < mirrorX + 12 && y >= cellY && y < cellY + 12) return true;
      }
    }
  }
  return false;
}

function setPixel(pixels: Uint8Array, x: number, y: number, color: Rgb, alpha = 255): void {
  const offset = y * (IDENTICON_SIZE * 4 + 1) + 1 + x * 4;
  pixels[offset] = color[0];
  pixels[offset + 1] = color[1];
  pixels[offset + 2] = color[2];
  pixels[offset + 3] = alpha;
}

function rasterizeIdenticon(hash: Uint8Array, background: Rgb, foreground: Rgb): PngBytes {
  const scanlines = new Uint8Array(new ArrayBuffer(IDENTICON_SIZE * (IDENTICON_SIZE * 4 + 1)));
  for (let y = 0; y < IDENTICON_SIZE; y++) {
    const sourceY = (y + 0.5) * SOURCE_SIZE / IDENTICON_SIZE;
    const rowOffset = y * (IDENTICON_SIZE * 4 + 1);
    scanlines[rowOffset] = 0;
    for (let x = 0; x < IDENTICON_SIZE; x++) {
      const sourceX = (x + 0.5) * SOURCE_SIZE / IDENTICON_SIZE;
      if (!isInsideRoundedBackground(sourceX, sourceY)) continue;
      const color = isInsideMark(sourceX, sourceY, hash) ? foreground : background;
      setPixel(scanlines, x, y, color);
      if ((sourceX - (26 + (hash[20] % 4) * 12)) ** 2 + (sourceY - (26 + (hash[21] % 4) * 12)) ** 2 <= 4 ** 2) {
        setPixel(scanlines, x, y, [
          Math.round(color[0] * 0.28 + 255 * 0.72),
          Math.round(color[1] * 0.28 + 255 * 0.72),
          Math.round(color[2] * 0.28 + 255 * 0.72),
        ]);
      }
    }
  }
  return scanlines;
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function createPngChunk(type: string, data: Uint8Array): PngBytes {
  const chunk = new Uint8Array(new ArrayBuffer(data.length + 12));
  const view = new DataView(chunk.buffer);
  view.setUint32(0, data.length);
  chunk.set(new TextEncoder().encode(type), 4);
  chunk.set(data, 8);
  view.setUint32(chunk.length - 4, crc32(chunk.subarray(4, chunk.length - 4)));
  return chunk;
}

function joinPngChunks(chunks: readonly Uint8Array[]): PngBytes {
  const image: PngBytes = new Uint8Array(new ArrayBuffer(chunks.reduce((total, chunk) => total + chunk.length, 0)));
  let offset = 0;
  for (const chunk of chunks) {
    image.set(chunk, offset);
    offset += chunk.length;
  }
  return image;
}

async function renderIdenticon(handle: string): Promise<PngBytes> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(handle));
  const hash = new Uint8Array(digest);
  const backgroundName = IDENTICON_PALETTE[hash[0] % IDENTICON_PALETTE.length];
  let foregroundIndex = hash[1] % IDENTICON_PALETTE.length;
  if (IDENTICON_PALETTE[foregroundIndex] === backgroundName) foregroundIndex = (foregroundIndex + 1) % IDENTICON_PALETTE.length;
  const scanlines = rasterizeIdenticon(hash, parseColor(backgroundName), parseColor(IDENTICON_PALETTE[foregroundIndex]));
  const stream = new CompressionStream('deflate');
  const writer = stream.writable.getWriter();
  await writer.write(scanlines);
  await writer.close();
  const idat = new Uint8Array(await new Response(stream.readable).arrayBuffer());
  const ihdr = new Uint8Array(new ArrayBuffer(13));
  const view = new DataView(ihdr.buffer);
  view.setUint32(0, IDENTICON_SIZE);
  view.setUint32(4, IDENTICON_SIZE);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return joinPngChunks([PNG_SIGNATURE, createPngChunk('IHDR', ihdr), createPngChunk('IDAT', idat), createPngChunk('IEND', new Uint8Array())]);
}

routes.get('/:handle/avatar.png', async (c) => {
  const handle = c.req.param('handle');
  if (!handle) return c.text('not found', 404);
  const png = await renderIdenticon(handle);
  return new Response(png, { headers: { 'content-type': 'image/png', 'cache-control': 'public, max-age=31536000, immutable' } });
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
