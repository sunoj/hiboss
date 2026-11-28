// Sends one resolved destination through existing APNs adapter.
// Exports sendDestination; depends on persisted metadata and push payload builders.
import type { Env, MessageRow } from '../types';
import { sendDevicePush, type PushDevice } from '../push/send';
import { liveDeviceSql } from '../push/devices';
import { prepareBossPush } from '../push/boss-payload';
import { jsonObject, type ResolvedDestination } from './types';

export async function sendDestination(env: Env, destination: ResolvedDestination, message: MessageRow): Promise<string | null> {
  // Native streams already expose stored messages; this is eligibility, not a receipt.
  if (destination.kind === 'native_live') return null;
  const agent = await env.DB.prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(message.agent_id).first<{ name: string }>();
  const session = await env.DB.prepare('SELECT label, branch FROM sessions WHERE id = ? AND agent_id = ?')
    .bind(message.session_id, message.agent_id).first<{ label: string | null; branch: string | null }>();
  return sendApns(env, destination, message, agent?.name ?? 'agent', session);
}

async function sendApns(env: Env, destination: ResolvedDestination, message: MessageRow, agent: string,
  session: { label: string | null; branch: string | null } | null): Promise<null> {
  const device = await env.DB.prepare(`SELECT d.boss_id, d.device_token, d.bundle_id, d.environment, d.relay_handle,
      d.push_key FROM boss_devices d
    WHERE d.id = ? AND d.boss_id = ? AND d.client_id IS ? AND ${liveDeviceSql('d')}`)
    .bind(destination.config.device_id, destination.boss_id, destination.client_id)
    .first<PushDevice>();
  if (!device) throw new Error('push device unavailable');
  const preferences = jsonObject(destination.preferences);
  // Destination thresholds own eligibility; retain privacy and presentation preferences.
  const push = typeof preferences.push === 'object' && preferences.push ? preferences.push as Record<string, unknown> : {};
  const tier = typeof push[message.priority] === 'object' && push[message.priority] ? push[message.priority] as Record<string, unknown> : {};
  const prepared = prepareBossPush(message, agent, session, destination.boss_id,
    JSON.stringify({ ...preferences, push: { ...push, [message.priority]: { ...tier, deliver: true } } }));
  if (!prepared) throw new Error('push payload unavailable');
  const result = await sendDevicePush(env, device, prepared.payload, prepared.apnsPriority);
  if (!result.ok) throw new Error(result.reason);
  return null;
}
