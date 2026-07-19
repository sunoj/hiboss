// Best-effort webhook notification to agent callback URLs.
// Exports notifyAgentCallback and notifyBossAgents for push delivery.
// Depends on D1 for callback lookup and global fetch for delivery.

import { hasApnsConfig, sendPush, type ApnsEnvironment, type ApnsPayload } from './apns';
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
  for (const device of devices.results) {
    try {
      const payload = buildBossPushPayload(message, agentName, device.boss_id);
      const result = await sendPush(env, device.device_token, device.environment, device.bundle_id, payload);
      if (result.prune) {
        await env.DB.prepare('DELETE FROM boss_devices WHERE device_token = ?').bind(device.device_token).run();
      }
    } catch {
      // Best-effort per device.
    }
  }
}

function buildBossPushPayload(message: MessageRow, agentName: string, bossId: string): ApnsPayload {
  const options = extractOptions(message.metadata);
  const payload: ApnsPayload = {
    aps: {
      alert: { title: agentName || 'HiBoss', body: truncateBody(message.body) },
      sound: 'default',
      'interruption-level': interruptionLevel(message.priority),
      'thread-id': bossId,
    },
    messageId: message.id,
    agentName,
    priority: message.priority,
    direction: message.direction,
    category: options ? 'HIBOSS_OPTIONS' : 'HIBOSS_MESSAGE',
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

function interruptionLevel(priority: Priority): 'active' | 'time-sensitive' | 'critical' {
  if (priority === 'critical') return 'critical';
  if (priority === 'high') return 'time-sensitive';
  return 'active';
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
