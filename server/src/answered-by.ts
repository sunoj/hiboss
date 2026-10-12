// Server-owned attribution for replies made by registered boss clients.
// Exports metadata stamping and tolerant reads for additive reply/stream JSON.
// Depends on boss client kinds and D1; labels come only from stored client rows.

import type { ClientId, ClientKind } from './boss-clients/types';
import type { Env, Metadata } from './types';

export interface AnsweredBy {
  client_id: string;
  kind: ClientKind;
  label: string;
}

export async function stampAnsweredBy(
  env: Env, bossId: string, clientId: ClientId | null, metadata: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const { answered_by: ignored, ...trusted } = metadata;
  const client = clientId ? await env.DB.prepare(
    'SELECT id AS client_id, kind, label FROM boss_clients WHERE id = ? AND boss_id = ?',
  ).bind(clientId, bossId).first<AnsweredBy>() : null;
  return client ? { ...trusted, answered_by: client } : trusted;
}

export function readAnsweredBy(metadata: Metadata): AnsweredBy | undefined {
  const value = metadata?.['answered_by'];
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  const kind = record['kind'];
  if (typeof record['client_id'] !== 'string' || typeof record['label'] !== 'string') return undefined;
  if (kind !== 'ios' && kind !== 'macos' && kind !== 'web' && kind !== 'cli') return undefined;
  return { client_id: record['client_id'], kind, label: record['label'] };
}
