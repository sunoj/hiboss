// Shared progress-feed parsing, identity mapping, and response types.
// Exports progress payload helpers, team mapping, and post SQL row mapping.
// Depends on Hono request URLs and the worker Env type.

import type { Context } from 'hono';
import type { Env } from '../types';

export type MediaKind = 'image' | 'video';

export interface MediaItem {
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

export interface ProgressTeam {
  handle: string;
  display_name: string;
  avatar_url: string;
  registered: boolean;
}

export interface TeamProfile extends ProgressTeam {
  project: string;
  bio: string | null;
}

export interface ProgressPost {
  id: string;
  project: string;
  agent_id: string;
  agent_name: string;
  session_id: string | null;
  body: string;
  media: MediaItem[];
  tags: string[];
  created_at: string;
  team: ProgressTeam;
  like_count: number;
  liked: boolean;
}

export interface ProgressRow {
  id: string;
  agent_id: string;
  agent_name: string;
  session_id: string | null;
  project: string;
  body: string;
  media: string | null;
  tags: string | null;
  created_at: string;
  team_handle: string | null;
  team_display_name: string | null;
  team_avatar_url: string | null;
  like_count: number;
  liked: number;
}

export interface TeamRow {
  project: string;
  handle: string | null;
  display_name: string | null;
  bio: string | null;
  avatar_url: string | null;
}

export interface CreatePayload {
  body: string;
  project: string | null;
  session_id: string | null;
  media: MediaItem[] | null;
  tags: string[] | null;
}

export interface ProgressCursor {
  created_at: string;
  id: string;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

export function getAttachmentKey(value: string, requestUrl: URL): string | null {
  try {
    const url = new URL(value);
    const prefix = '/api/attachments/';
    if (url.origin !== requestUrl.origin || !url.pathname.startsWith(prefix)) return null;
    const key = url.pathname.slice(prefix.length);
    return key && !key.includes('/') ? key : null;
  } catch {
    return null;
  }
}

export function parseMediaItem(value: unknown, requestUrl: URL): MediaItem | string {
  if (!isRecord(value)) return 'media items must be objects';
  if (typeof value.url !== 'string' || !getAttachmentKey(value.url, requestUrl)) {
    return 'media URLs must point to this worker attachments path';
  }
  if (value.kind !== 'image' && value.kind !== 'video') return 'media kind must be image or video';
  if (typeof value.content_type !== 'string' || !value.content_type) return 'media content_type is required';
  if (!isNonNegativeInteger(value.size)) return 'media size must be a non-negative integer';
  for (const field of ['width', 'height', 'duration_ms']) {
    if (value[field] !== undefined && !isNonNegativeInteger(value[field])) return `media ${field} must be a non-negative integer`;
  }
  if (value.poster_url !== undefined && (typeof value.poster_url !== 'string' || !getAttachmentKey(value.poster_url, requestUrl))) {
    return 'poster URLs must point to this worker attachments path';
  }
  if (value.alt !== undefined && typeof value.alt !== 'string') return 'media alt must be a string';
  return value as unknown as MediaItem;
}

export async function parseCreatePayload(c: Context<{ Bindings: Env }>): Promise<CreatePayload | string> {
  let input: unknown;
  try {
    input = await c.req.json<unknown>();
  } catch {
    return 'invalid JSON body';
  }
  if (!isRecord(input) || typeof input.body !== 'string') return 'body is required';
  if (!input.body.trim()) return 'body must not be empty';
  if (input.body.length > 2000) return 'body is too long (max 2000 characters)';
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

export async function verifyMediaOwnership(
  c: Context<{ Bindings: Env }>,
  media: MediaItem[],
  agentId: string,
): Promise<string | null> {
  const requestUrl = new URL(c.req.url);
  for (const item of media) {
    const urls = item.poster_url ? [item.url, item.poster_url] : [item.url];
    for (const url of urls) {
      const key = getAttachmentKey(url, requestUrl);
      if (!key) return 'media URLs must point to this worker attachments path';
      const object = await c.env.ATTACHMENTS.head(key);
      if (!object || object.customMetadata?.agent_id !== agentId) {
        return 'media attachment does not exist or belongs to another agent';
      }
    }
  }
  return null;
}

export function normalizeTimestamp(value: string): string {
  const iso = value.includes('T') ? value : value.replace(' ', 'T');
  return iso.endsWith('Z') ? iso : `${iso}Z`;
}

export function parseArray<T>(value: string | null): T[] {
  if (!value) return [];
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed as T[] : [];
  } catch {
    return [];
  }
}

export function slugifyProject(project: string): string {
  const slug = project.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 32);
  return slug || 'team';
}

export function generatedAvatarUrl(requestUrl: URL, handle: string): string {
  return `${requestUrl.origin}/api/progress/teams/${encodeURIComponent(handle)}/avatar.svg`;
}

export function mapTeamRow(row: TeamRow, requestUrl: URL): TeamProfile {
  const registered = row.handle !== null;
  const handle = row.handle ?? slugifyProject(row.project);
  return {
    project: row.project,
    handle,
    display_name: row.display_name ?? row.project,
    bio: row.bio,
    avatar_url: row.avatar_url ?? generatedAvatarUrl(requestUrl, handle),
    registered,
  };
}

export function mapProgressRow(row: ProgressRow, requestUrl: URL, bossAuthenticated: boolean): ProgressPost {
  const team = mapTeamRow({
    project: row.project,
    handle: row.team_handle,
    display_name: row.team_display_name,
    bio: null,
    avatar_url: row.team_avatar_url,
  }, requestUrl);
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
    team: { handle: team.handle, display_name: team.display_name, avatar_url: team.avatar_url, registered: team.registered },
    like_count: Number(row.like_count ?? 0),
    liked: bossAuthenticated && row.liked === 1,
  };
}

export function progressSelect(): string {
  return `SELECT p.*, a.name AS agent_name, t.handle AS team_handle, t.display_name AS team_display_name, t.avatar_url AS team_avatar_url, (SELECT COUNT(*) FROM progress_likes l WHERE l.post_id = p.id) AS like_count, EXISTS (SELECT 1 FROM progress_likes l WHERE l.post_id = p.id AND l.boss_id = ?) AS liked FROM progress_posts p JOIN api_keys a ON a.id = p.agent_id LEFT JOIN progress_teams t ON t.project = p.project`;
}
