// Box item contracts shared by ingestion, persistence and HTTP responses.
// Exports strictly typed item metadata and Hono context aliases.
import type { Context } from 'hono';
import type { Env } from '../types';

export type BoxContext = Context<{ Bindings: Env }>;
export const KINDS = ['link', 'text', 'image', 'video', 'file'] as const;
export const SOURCES = ['ios-share', 'mac-share', 'mac-drop', 'cli'] as const;
export type BoxKind = typeof KINDS[number];
export type BoxSource = typeof SOURCES[number];

export interface BoxMetadata {
  text: string | null;
  url: string | null;
  note: string | null;
  project: string | null;
  tags: string[];
  source: BoxSource;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
}

export interface BoxRow extends Omit<BoxMetadata, 'tags'> {
  id: string;
  boss_id: string;
  boss_name: string;
  agent_id: string | null;
  agent_name: string | null;
  kind: BoxKind;
  tags: string;
  media_key: string | null;
  media_type: string | null;
  media_bytes: number | null;
  thumb_key: string | null;
  thumb_bytes: number | null;
  created_at: string;
  deleted_at: string | null;
  liked_at: string | null;
  collection_ids: string;
}

export type BoxAuthor = { kind: 'boss' } | { kind: 'agent'; id: string; name: string };
export type BoxItem = Omit<BoxRow,
  'tags' | 'media_key' | 'thumb_key' | 'thumb_bytes' | 'deleted_at' | 'agent_id' | 'agent_name'
  | 'collection_ids'> & { tags: string[]; has_media: boolean; has_thumbnail: boolean;
  added_by: BoxAuthor; liked: boolean; collection_ids: string[] };

export interface BoxWriteScope {
  bossId: string;
  agentId: string | null;
}

export interface BoxUpload {
  meta: BoxMetadata;
  kind: BoxKind;
  file: File | null;
  thumbnail: BoxThumbnail | null;
  boss: string | null;
}

export interface BoxThumbnail {
  type: string;
  bytes: Uint8Array;
}

export type BoxCursor = { created_at: string; id: string };

export interface BoxFilter {
  sql: string;
  binds: (string | number)[];
  limit: number;
  cursor: BoxCursor | null;
}

export function itemResponse(row: BoxRow): BoxItem {
  const { media_key, thumb_key, thumb_bytes, deleted_at, agent_id, agent_name, collection_ids,
    ...item } = row;
  const added_by: BoxAuthor = agent_id === null ? { kind: 'boss' }
    : { kind: 'agent', id: agent_id, name: agent_name ?? agent_id };
  return { ...item, liked: row.liked_at !== null,
    collection_ids: JSON.parse(collection_ids) as string[], tags: JSON.parse(row.tags) as string[],
    has_media: media_key !== null, has_thumbnail: thumb_key !== null, added_by };
}
