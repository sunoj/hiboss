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
  kind: BoxKind;
  tags: string;
  media_key: string | null;
  media_type: string | null;
  media_bytes: number | null;
  created_at: string;
  deleted_at: string | null;
}

export type BoxItem = Omit<BoxRow, 'tags' | 'media_key' | 'deleted_at'>
  & { tags: string[]; has_media: boolean };

export interface BoxUpload {
  meta: BoxMetadata;
  kind: BoxKind;
  file: File | null;
}

export interface BoxCursor {
  created_at: string;
  id: string;
  score?: number;
}

export interface BoxFilter {
  sql: string;
  binds: (string | number)[];
  limit: number;
  cursor: BoxCursor | null;
}

export function itemResponse(row: BoxRow): BoxItem {
  const { media_key, deleted_at, ...item } = row;
  return { ...item, tags: JSON.parse(row.tags) as string[], has_media: media_key !== null };
}
