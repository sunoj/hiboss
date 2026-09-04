// Best-effort webhook notification to agent callback URLs.
// Exports notifyAgentCallback and notifyBossAgents for push delivery.
// Depends on D1 for callback lookup and global fetch for delivery.

import {
  hasApnsConfig,
  sendPush,
  type ApnsEnvironment,
} from './apns';
import { prepareBossPush, type BossPushSession } from './push/boss-payload';
import type { Env, MessageRow } from './types';

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

export async function notifyAgentCallback(env: Env, agentId: string, message: MessageRow, markDelivered = false): Promise<void> {
  try {
    const row = await env.DB
      .prepare('SELECT callback_url FROM api_keys WHERE id = ?')
      .bind(agentId)
      .first<{ callback_url: string | null }>();
    if (!row?.callback_url) {
      return;
    }
    const response = await fetch(row.callback_url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });
    if (markDelivered && response.ok && message.direction === 'agent_to_agent') {
      await env.DB
        .prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ? AND direction = 'agent_to_agent' AND status = 'sent'")
        .bind(message.id)
        .run();
    }
  } catch {
    // Best-effort: swallow errors to avoid disrupting the webhook response.
  }
}

/** Notify target agent via callback URL for agent-to-agent messages. */
export async function notifyTargetAgent(env: Env, targetAgentId: string, message: MessageRow): Promise<void> {
  await notifyAgentCallback(env, targetAgentId, message, true);
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
  const session = await fetchSessionLabel(env, message.session_id);
  const preferencesByBoss = new Map(bosses.map((boss) => [boss.id, boss.preferences]));
  for (const device of devices.results) {
    const prefs = preferencesByBoss.get(device.boss_id);
    const prepared = prepareBossPush(message, agentName, session, device.boss_id, prefs);
    if (!prepared) continue;
    try {
      const result = await sendPush(
        env,
        device.device_token,
        device.environment,
        device.bundle_id,
        prepared.payload,
        prepared.apnsPriority,
      );
      if (result.prune) {
        await env.DB.prepare('DELETE FROM boss_devices WHERE device_token = ?').bind(device.device_token).run();
      }
    } catch {
      // Best-effort per device.
    }
  }
}

async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
}

async function fetchSessionLabel(
  env: Env,
  sessionId: string | null | undefined,
): Promise<BossPushSession | null> {
  if (!sessionId) return null;
  const row = await env.DB
    .prepare('SELECT label, branch FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<BossPushSession>();
  return row ?? null;
}
