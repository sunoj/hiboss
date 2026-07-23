// Best-effort webhook notification to agent callback URLs.
// Exports notifyAgentCallback and notifyBossAgents for push delivery.
// Depends on D1 for callback lookup and global fetch for delivery.

import {
  hasApnsConfig,
  sendPush,
  type ApnsEnvironment,
  type ApnsInterruptionLevel,
  type ApnsPayload,
  type ApnsPriority,
} from './apns';
import type { Env, MessageRow, Priority } from './types';

interface BossRecipientRow {
  id: string;
  agent_id: string | null;
  preferences: string | null;
}

interface BossDeviceRow {
  boss_id: string;
  device_token: string;
  bundle_id: string;
  environment: ApnsEnvironment;
}

export async function notifyAgentCallback(env: Env, agentId: string, message: MessageRow): Promise<void> {
  try {
    const row = await env.DB
      .prepare('SELECT callback_url FROM api_keys WHERE id = ?')
      .bind(agentId)
      .first<{ callback_url: string | null }>();
    if (!row?.callback_url) {
      return;
    }
    await fetch(row.callback_url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });
  } catch {
    // Best-effort: swallow errors to avoid disrupting the webhook response.
  }
}

/** Notify target agent via callback URL for agent-to-agent messages. */
export async function notifyTargetAgent(env: Env, targetAgentId: string, message: MessageRow): Promise<void> {
  await notifyAgentCallback(env, targetAgentId, message);
}

/** Notify boss-agents who have access to the given sub-agent. */
export async function notifyBossAgents(env: Env, subAgentId: string, message: MessageRow): Promise<void> {
  try {
    const rows = await env.DB
      .prepare(
        `SELECT b.id, b.agent_id, b.preferences FROM bosses b
         WHERE (
           b.role = 'admin'
           OR b.id IN (SELECT boss_id FROM boss_agent_access WHERE agent_id = ?)
         )`
      )
      .bind(subAgentId)
      .all<BossRecipientRow>();
    for (const row of rows.results ?? []) {
      if (row.agent_id) {
        await notifyAgentCallback(env, row.agent_id, message);
      }
    }
    await notifyBossDevices(env, rows.results ?? [], subAgentId, message);
  } catch {
    // Best-effort
  }
}

async function notifyBossDevices(
  env: Env,
  bosses: BossRecipientRow[],
  subAgentId: string,
  message: MessageRow,
): Promise<void> {
  if (message.direction !== 'agent_to_boss' || bosses.length === 0 || !hasApnsConfig(env)) return;
  const bossIds = bosses.map((boss) => boss.id);
  const placeholders = bossIds.map(() => '?').join(', ');
  const devices = await env.DB
    .prepare(`SELECT boss_id, device_token, bundle_id, environment FROM boss_devices WHERE boss_id IN (${placeholders})`)
    .bind(...bossIds)
    .all<BossDeviceRow>();
  if (!devices.results?.length) return;
  const agentName = message.agent_name ?? await fetchAgentName(env, subAgentId) ?? 'HiBoss';
  const options = extractOptions(message.metadata);
  const isDecision = options !== undefined && options.length > 0;
  const preferencesByBoss = new Map(bosses.map((boss) => [boss.id, boss.preferences]));
  for (const device of devices.results) {
    const prefs = preferencesByBoss.get(device.boss_id);
    const tier = pushTier(message.priority, isDecision, prefs);
    if (!tier.deliver) continue;
    try {
      const payload = buildBossPushPayload(message, agentName, device.boss_id, tier, isPrivatePush(prefs));
      const result = await sendPush(
        env, device.device_token, device.environment, device.bundle_id, payload, tier.apnsPriority,
      );
      if (result.prune) {
        await env.DB.prepare('DELETE FROM boss_devices WHERE device_token = ?').bind(device.device_token).run();
      }
    } catch {
      // Best-effort per device.
    }
  }
}

function buildBossPushPayload(
  message: MessageRow,
  agentName: string,
  bossId: string,
  tier: PushTier,
  privatePush: boolean,
): ApnsPayload {
  const options = extractOptions(message.metadata);
  // Private mode keeps message content off Apple's servers: the payload carries
  // only a generic alert + the message id, and the app fetches the body itself.
  const category = privatePush ? 'HIBOSS_MESSAGE' : (options ? 'HIBOSS_OPTIONS' : 'HIBOSS_MESSAGE');
  const summary = extractSummary(message.metadata);
  const body = privatePush
    ? (summary ?? (options ? `New decision from ${agentName}` : `New message from ${agentName}`))
    : truncateBody(message.body);
  const aps: ApnsPayload['aps'] = {
    alert: { title: privatePush ? 'HiBoss' : (agentName || 'HiBoss'), body },
    'interruption-level': tier.level,
    'thread-id': bossId,
    // iOS renders the notification's action buttons from aps.category.
    category,
  };
  // Only interruptive tiers make a sound; quiet tiers land silently.
  if (tier.sound) {
    aps.sound = 'default';
  }
  const payload: ApnsPayload = {
    aps,
    messageId: message.id,
    agentName,
    priority: message.priority,
    direction: message.direction,
    category,
  };
  // Omit option text from the payload in private mode so no content reaches APNs.
  if (options && !privatePush) {
    payload.options = options;
  }
  return payload;
}

/** Agent-supplied non-sensitive summary shown in private-mode pushes. */
function extractSummary(metadata: string | null): string | undefined {
  if (!metadata) return undefined;
  try {
    const parsed = JSON.parse(metadata) as { summary?: unknown };
    const summary = typeof parsed.summary === 'string' ? parsed.summary.trim() : '';
    return summary.length > 0 ? summary : undefined;
  } catch {
    return undefined;
  }
}

function isPrivatePush(preferences: string | null | undefined): boolean {
  if (!preferences) return false;
  try {
    const parsed = JSON.parse(preferences) as Record<string, unknown>;
    return parsed.private_push === true;
  } catch {
    return false;
  }
}

function extractOptions(metadata: string | null): string[] | undefined {
  if (!metadata) return undefined;
  try {
    const parsed = JSON.parse(metadata) as unknown;
    if (!parsed || typeof parsed !== 'object') return undefined;
    const options = (parsed as { options?: unknown }).options;
    return Array.isArray(options) && options.every((option): option is string => typeof option === 'string')
      ? options
      : undefined;
  } catch {
    return undefined;
  }
}

interface PushTier {
  deliver: boolean;
  sound: boolean;
  level: ApnsInterruptionLevel;
  apnsPriority: ApnsPriority;
}

interface PushPreferenceOverride {
  deliver?: boolean;
  sound?: boolean;
  level?: 'passive' | 'active' | 'time-sensitive' | 'critical';
}

// Maps a message's priority to how intrusive its push is. A pending decision
// (carries options) always alerts. Plain status messages tier down by priority:
// normal is silent/passive; low is not pushed at all (visible in-app only).
// critical uses 'time-sensitive' (safe without the critical-alerts entitlement).
function pushTier(priority: Priority, isDecision: boolean, preferences: string | null | undefined): PushTier {
  if (isDecision) {
    return priority === 'critical'
      ? { deliver: true, sound: true, level: 'time-sensitive', apnsPriority: '10' }
      : { deliver: true, sound: true, level: 'active', apnsPriority: '10' };
  }
  const base = defaultStatusPushTier(priority);
  const override = statusPushOverride(priority, preferences);
  if (!override) return base;
  const sound = override.sound ?? base.sound;
  const level = normalizeInterruptionLevel(override.level ?? base.level);
  return {
    deliver: override.deliver ?? base.deliver,
    sound,
    level,
    apnsPriority: apnsPriorityFor(sound, level),
  };
}

function defaultStatusPushTier(priority: Priority): PushTier {
  switch (priority) {
    case 'critical':
      return { deliver: true, sound: true, level: 'time-sensitive', apnsPriority: '10' };
    case 'high':
      return { deliver: true, sound: true, level: 'active', apnsPriority: '10' };
    case 'normal':
      return { deliver: true, sound: false, level: 'passive', apnsPriority: '5' };
    case 'low':
      return { deliver: false, sound: false, level: 'passive', apnsPriority: '5' };
    default:
      return { deliver: true, sound: false, level: 'passive', apnsPriority: '5' };
  }
}

function statusPushOverride(priority: Priority, preferences: string | null | undefined): PushPreferenceOverride | null {
  if (!preferences) return null;
  try {
    const parsed = JSON.parse(preferences) as Record<string, unknown>;
    const push = parsed['push'];
    if (!push || typeof push !== 'object' || Array.isArray(push)) return null;
    const priorityOverride = (push as Record<string, unknown>)[priority];
    if (!priorityOverride || typeof priorityOverride !== 'object' || Array.isArray(priorityOverride)) return null;
    const raw = priorityOverride as Record<string, unknown>;
    return {
      deliver: typeof raw['deliver'] === 'boolean' ? raw['deliver'] : undefined,
      sound: typeof raw['sound'] === 'boolean' ? raw['sound'] : undefined,
      level: pushLevel(raw['level']),
    };
  } catch {
    return null;
  }
}

function pushLevel(value: unknown): PushPreferenceOverride['level'] {
  return value === 'passive' || value === 'active' || value === 'time-sensitive' || value === 'critical'
    ? value
    : undefined;
}

function normalizeInterruptionLevel(level: PushPreferenceOverride['level']): ApnsInterruptionLevel {
  return level === 'critical' ? 'time-sensitive' : level ?? 'passive';
}

function apnsPriorityFor(sound: boolean, level: ApnsInterruptionLevel): ApnsPriority {
  return sound || level === 'active' || level === 'time-sensitive' ? '10' : '5';
}

function truncateBody(body: string): string {
  return body.length > 150 ? `${body.slice(0, 147)}...` : body;
}

async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
}
