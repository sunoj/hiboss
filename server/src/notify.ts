// Best-effort webhook notification to agent callback URLs.
// Exports agent callbacks and boss message/questionnaire push delivery.
// Depends on D1 for callback lookup and global fetch for delivery.

import {
  hasApnsConfig,
  sendPush,
  type ApnsEnvironment,
} from './apns';
import { prepareBossPush, type BossPushSession, type PreparedBossPush } from './push/boss-payload';
import { deleteBossDevice } from './push/devices';
import { prepareRequestPush } from './push/request-payload';
import type { Questionnaire } from './panels/requests/types';
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
         WHERE b.archived_at IS NULL AND (
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
    if (env.DESTINATIONS_MODE !== 'on') await notifyBossDevices(env, rows.results ?? [], subAgentId, message);
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
    await sendBossDevicePush(env, device, prepared);
  }
}

export async function notifyBossRequest(env: Env, panelId: string, requestId: string, form: Questionnaire): Promise<void> {
  if (!form.blocking || env.DESTINATIONS_MODE === 'on' || !hasApnsConfig(env)) return;
  try {
    const panel = await env.DB.prepare(`SELECT p.target_boss_id, p.agent_id, p.title, b.preferences
      FROM panels p JOIN bosses b ON b.id = p.target_boss_id WHERE p.panel_id = ? AND b.archived_at IS NULL`).bind(panelId)
      .first<{ target_boss_id: string; agent_id: string; title: string | null; preferences: string | null }>();
    if (!panel) return;
    const agentName = await fetchAgentName(env, panel.agent_id) ?? 'HiBoss';
    const prepared = prepareRequestPush({ panelId, requestId, bossId: panel.target_boss_id, agentName,
      panelTitle: panel.title, title: form.title, priority: form.priority }, panel.preferences);
    if (!prepared) return;
    const devices = await env.DB.prepare('SELECT boss_id, device_token, bundle_id, environment FROM boss_devices WHERE boss_id = ?')
      .bind(panel.target_boss_id).all<BossDeviceRow>();
    for (const device of devices.results ?? []) await sendBossDevicePush(env, device, prepared);
  } catch {
    // Best-effort: publication remains successful even if push preparation fails.
  }
}

async function sendBossDevicePush(env: Env, device: BossDeviceRow, prepared: PreparedBossPush): Promise<void> {
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
      await deleteBossDevice(env, device.boss_id, device.device_token);
    }
  } catch {
    // Best-effort per device.
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
