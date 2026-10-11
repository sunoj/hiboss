// Parses send requests and selects legacy channels only in off/shadow mode.
// Exports prepareSendInput and its inferred contract; depends on shared validators.
import type { Context } from 'hono';
import type { Env, Mode, Priority, Channel, OptionMedia } from '../types';
import { getAgentId } from '../middleware/auth';
import { destinationsMode } from '../delivery';
import { checkRateLimit, validateOption, priorityOptions, validateChannel, resolveChannelRouting, parseOptions, normalizeMetadata, parseOptionMedia, fetchAllChannelConfigs, selectChannelConfig } from './message-helpers';
const modeOptions: Mode[] = ['async', 'blocking'];
export interface SendInput {
  agentId: string;
  payload: Record<string, unknown>;
  body: string;
  idempotencyKey: string | null;
  agentConfig: { default_priority: string; rate_limit: number | null; channel_routing: string | null; avatar_url: string | null } | null;
  mode: Mode;
  priority: Priority;
  requestedChannel: Channel | undefined;
  fileUrl: string | undefined;
  messageType: string;
  sessionId: string | null;
  toAgent: string | null;
  options: string[] | undefined;
  optionMediaResult: { ok: true; value: OptionMedia[] | undefined };
  metadata: Record<string, unknown> | null;
  channelConfigs: { channel: Channel; config: Record<string, unknown> }[];
}
export async function prepareSendInput(c: Context<{ Bindings: Env }>): Promise<Response | SendInput> {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const idempotencyKey = typeof payload.idempotency_key === 'string' ? payload.idempotency_key.trim() || null : null;
  const agentConfig = await c.env.DB
    .prepare('SELECT default_priority, rate_limit, channel_routing, avatar_url FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ default_priority: string; rate_limit: number | null; channel_routing: string | null; avatar_url: string | null }>();
  const defaultPriority = (agentConfig?.default_priority ?? 'normal') as Priority;
  if (agentConfig?.rate_limit && await checkRateLimit(c.env, agentId, agentConfig.rate_limit)) {
    return c.text('rate limit exceeded', 429);
  }
  const mode = validateOption<Mode>(payload.mode, modeOptions, 'async') as Mode;
  const priority = validateOption<Priority>(payload.priority, priorityOptions, defaultPriority) as Priority;
  const explicitChannel = validateChannel(payload.channel);
  const routedChannel = !explicitChannel && agentConfig?.channel_routing
    ? resolveChannelRouting(agentConfig.channel_routing, priority as string)
    : undefined;
  const requestedChannel = explicitChannel ?? routedChannel;
  const fileUrl = typeof payload.file_url === 'string' ? payload.file_url.trim() : undefined;
  const messageType = typeof payload.type === 'string' ? payload.type.trim() : 'text';
  const sessionId = typeof payload.session_id === 'string' ? payload.session_id.trim() || null : null;
  const toAgent = typeof payload.to === 'string' ? payload.to.trim() || null : null;
  const optionsResult = parseOptions(payload.options);
  if (!optionsResult.ok) return c.text(optionsResult.error, 400);
  const options = optionsResult.value;
  const rawMetadata = normalizeMetadata(payload.metadata) ?? {};
  const optionMediaResult = parseOptionMedia(rawMetadata['option_media'], options);
  if (!optionMediaResult.ok) return c.text(optionMediaResult.error, 400);
  if (fileUrl) (rawMetadata as Record<string, unknown>)['file_url'] = fileUrl;
  if (options) (rawMetadata as Record<string, unknown>)['options'] = options;
  if (optionMediaResult.value) (rawMetadata as Record<string, unknown>)['option_media'] = optionMediaResult.value;
  const metadata = Object.keys(rawMetadata as Record<string, unknown>).length > 0 ? rawMetadata : null;
  const channelConfigs = await selectLegacyConfigs(c.env, agentId, priority, requestedChannel);
  return { agentId, payload, body, idempotencyKey, agentConfig, mode, priority, requestedChannel, fileUrl, messageType, sessionId, toAgent, options, optionMediaResult, metadata, channelConfigs };
}

async function selectLegacyConfigs(env: Env, agentId: string, priority: Priority, requestedChannel: Channel | undefined): Promise<{ channel: Channel; config: Record<string, unknown> }[]> {
  const isUrgent = priority === 'critical' || priority === 'high';
  let channelConfigs: { channel: Channel; config: Record<string, unknown> }[] = [];
  try {
    if (destinationsMode(env.DESTINATIONS_MODE) === 'on') {
      channelConfigs = [];
    } else if (isUrgent) {
      channelConfigs = await fetchAllChannelConfigs(env, agentId);
      if (requestedChannel) {
        // Put requested channel first, keep others
        channelConfigs.sort((a, b) => (a.channel === requestedChannel ? -1 : b.channel === requestedChannel ? 1 : 0));
      }
    } else {
      const single = await selectChannelConfig(env, agentId, requestedChannel);
      channelConfigs = [single];
    }
  } catch {
    // No channel configured — message will be stored without delivery.
  }
  return channelConfigs;
}
