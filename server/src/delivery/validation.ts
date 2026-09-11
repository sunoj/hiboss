// Validates the new destination/provider API without accepting legacy channels.
// Exports request parsers; depends only on destination contracts and priority constants.
import { PRIORITY_RANK } from './types';
import type { Priority } from '../types';

export type DestinationPatch = { enabled?: boolean; min_priority?: Priority; honours_quiet_hours?: boolean; label?: string };
export interface DestinationInput {
  kind: 'telegram_chat' | 'discord_channel';
  provider_id: string;
  label: string;
  target: Record<string, unknown>;
}
export interface ProviderInput {
  provider: 'telegram' | 'discord';
  label: string;
  credentials: Record<string, unknown>;
}
export function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
function label(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 100 && !/[\x00-\x1f]/.test(value);
}
function identifier(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= 200 && !/\s/.test(value);
}

export function parseDestinationPatch(value: unknown): DestinationPatch | null {
  const body = record(value);
  if (!body || !Object.keys(body).length) return null;
  if (Object.keys(body).some(key => !['enabled', 'min_priority', 'honours_quiet_hours', 'label'].includes(key))) return null;
  if ('enabled' in body && typeof body.enabled !== 'boolean') return null;
  if ('honours_quiet_hours' in body && typeof body.honours_quiet_hours !== 'boolean') return null;
  if ('min_priority' in body && (typeof body.min_priority !== 'string' || !Object.hasOwn(PRIORITY_RANK, body.min_priority))) return null;
  if ('label' in body && !label(body.label)) return null;
  return body as DestinationPatch;
}

export function parseDestination(value: unknown): DestinationInput | null {
  const body = record(value);
  if (!body || Object.keys(body).some(key => !['kind', 'provider_id', 'label', 'target'].includes(key))) return null;
  if (body.kind !== 'telegram_chat' && body.kind !== 'discord_channel') return null;
  if (!identifier(body.provider_id) || !label(body.label)) return null;
  const target = record(body.target);
  if (!target) return null;
  if (body.kind === 'telegram_chat') {
    if (!identifier(target.chat_id) || !/^-?\d+$/.test(target.chat_id)) return null;
    if (Object.keys(target).some(key => !['chat_id', 'message_thread_id', 'use_topics'].includes(key))) return null;
    if ('message_thread_id' in target && (!Number.isSafeInteger(target.message_thread_id) || Number(target.message_thread_id) <= 0)) return null;
    if ('use_topics' in target && typeof target.use_topics !== 'boolean') return null;
  } else {
    if (!identifier(target.channel_id) || !/^\d+$/.test(target.channel_id)) return null;
    if (Object.keys(target).some(key => !['channel_id', 'thread_id', 'use_threads'].includes(key))) return null;
    if ('thread_id' in target && (!identifier(target.thread_id) || !/^\d+$/.test(target.thread_id))) return null;
    if ('use_threads' in target && typeof target.use_threads !== 'boolean') return null;
  }
  return { kind: body.kind, provider_id: body.provider_id, label: body.label.trim(), target };
}

export function parseProvider(value: unknown): ProviderInput | null {
  const body = record(value);
  if (!body || Object.keys(body).some(key => !['provider', 'label', 'credentials'].includes(key))) return null;
  if ((body.provider !== 'telegram' && body.provider !== 'discord') || !label(body.label)) return null;
  const credentials = record(body.credentials);
  if (!credentials || Object.keys(credentials).some(key => !['bot_token', 'webhook_url', 'app_id'].includes(key))) return null;
  if (Object.values(credentials).some(value => !identifier(value))) return null;
  if (body.provider === 'telegram' && (!credentials.bot_token || credentials.webhook_url)) return null;
  if (body.provider === 'discord' && !credentials.bot_token && !credentials.webhook_url) return null;
  if (credentials.webhook_url) {
    try {
      const url = new URL(String(credentials.webhook_url));
      if (url.protocol !== 'https:' || url.hostname !== 'discord.com' || !/^\/api\/webhooks\/\d+\/[^/]+$/.test(url.pathname) || url.search || url.hash || url.username || url.password) return null;
    } catch { return null; }
  }
  return { provider: body.provider, label: body.label.trim(), credentials };
}
