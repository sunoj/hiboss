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
        `SELECT b.id, b.agent_id FROM bosses b
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
  const tier = pushTier(message.priority, options !== undefined && options.length > 0);
  // Low-priority status updates stay in-app only — no push at all.
  if (!tier.deliver) return;
  for (const device of devices.results) {
    try {
      const payload = buildBossPushPayload(message, agentName, device.boss_id, tier);
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
): ApnsPayload {
  const options = extractOptions(message.metadata);
  const category = options ? 'HIBOSS_OPTIONS' : 'HIBOSS_MESSAGE';
  const aps: ApnsPayload['aps'] = {
    alert: { title: agentName || 'HiBoss', body: truncateBody(message.body) },
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
  if (options) {
    payload.options = options;
  }
  return payload;
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

// Maps a message's priority to how intrusive its push is. A pending decision
// (carries options) always alerts. Plain status messages tier down by priority:
// normal is silent/passive; low is not pushed at all (visible in-app only).
// critical uses 'time-sensitive' (safe without the critical-alerts entitlement).
function pushTier(priority: Priority, isDecision: boolean): PushTier {
  if (isDecision) {
    return priority === 'critical'
      ? { deliver: true, sound: true, level: 'time-sensitive', apnsPriority: '10' }
      : { deliver: true, sound: true, level: 'active', apnsPriority: '10' };
  }
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
