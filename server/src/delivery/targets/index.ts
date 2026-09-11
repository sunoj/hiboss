// Groups effective targets and persists canonical send claims plus merged attribution.
// Exports grouping/recording helpers; depends on destination contracts and D1.
import type { Env } from '../../types';
import type { ResolvedDestination } from '../types';
export interface TargetGroup { key: string; destinations: ResolvedDestination[] }
export interface DeliveryRow {
  id: string; message_id: string; destination_id: string; attempts: number;
  next_attempt_at: string; external_target: string | null;
}
export async function fingerprint(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(value)));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}
export function chatTarget(kind: string, config: Record<string, unknown>): unknown[] {
  if (kind === 'telegram') return [String(config.chat_id ?? ''), String(config.message_thread_id ?? '')];
  // Webhooks own their base channel; bot APIs address threads as channel IDs.
  return config.webhook_url ? ['', String(config.thread_id ?? '')] : [String(config.channel_id ?? ''), ''];
}
async function targetKey(env: Env, row: ResolvedDestination): Promise<string> {
  if (row.kind === 'native_live') return fingerprint([row.kind, row.client_id]);
  if (row.kind === 'apns') {
    const device = await env.DB.prepare('SELECT device_token FROM boss_devices WHERE id = ? AND boss_id = ? AND client_id IS ?')
      .bind(row.config.device_id, row.boss_id, row.client_id).first<{ device_token: string }>();
    return fingerprint([row.kind, device?.device_token ?? row.id]);
  }
  return fingerprint([row.kind, row.provider_id, ...chatTarget(row.kind === 'telegram_chat' ? 'telegram' : 'discord', row.config)]);
}
export async function groupTargets(env: Env, rows: ResolvedDestination[]): Promise<TargetGroup[]> {
  const groups = new Map<string, ResolvedDestination[]>();
  for (const row of rows) {
    const key = await targetKey(env, row);
    const group = groups.get(key) ?? [];
    group.push(row);
    groups.set(key, group);
  }
  return [...groups].map(([key, destinations]) => ({ key, destinations: destinations.sort((a, b) =>
    (a.nextAttemptAt ?? '').localeCompare(b.nextAttemptAt ?? '') || a.id.localeCompare(b.id)) }));
}
export async function recordTarget(env: Env, messageId: string, group: TargetGroup, due: string | null): Promise<DeliveryRow | null> {
  const row = await env.DB.prepare(`INSERT INTO message_deliveries (message_id, destination_id, external_target, next_attempt_at)
    VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING RETURNING *`)
    .bind(messageId, group.destinations[0].id, group.key, due).first<DeliveryRow>();
  const primary = row ?? await env.DB.prepare('SELECT * FROM message_deliveries WHERE message_id = ? AND external_target = ?')
    .bind(messageId, group.key).first<DeliveryRow>();
  if (!primary) return null;
  for (const destination of group.destinations) {
    if (destination.id === primary.destination_id) continue;
    await env.DB.prepare(`INSERT INTO message_deliveries (message_id, destination_id, merged_into, status, external_message_id)
      SELECT message_id, ?, id, status, external_message_id FROM message_deliveries WHERE id = ?
      ON CONFLICT(message_id, destination_id) DO NOTHING`).bind(destination.id, primary.id).run();
  }
  return row;
}
export async function mirrorMerged(env: Env, id: string): Promise<void> {
  await env.DB.prepare(`UPDATE message_deliveries SET
    (status, external_message_id, last_error, updated_at) =
    (SELECT status, external_message_id, last_error, updated_at FROM message_deliveries WHERE id = ?)
    WHERE merged_into = ?`).bind(id, id).run();
}
