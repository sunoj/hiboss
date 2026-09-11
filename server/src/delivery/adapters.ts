// Sends one resolved destination through existing channel/APNs adapters.
// Exports sendDestination; depends on persisted metadata and push payload builders.
import type { Env, MessageRow } from '../types';
import { deliverToChannelWithOptions } from '../routes/delivery';
import { parseOptionMedia } from '../routes/option-media';
import { sendPush, type ApnsEnvironment } from '../apns';
import { prepareBossPush } from '../push/boss-payload';
import { jsonObject, type ResolvedDestination } from './types';

export async function sendDestination(env: Env, destination: ResolvedDestination, message: MessageRow): Promise<string | null> {
  // Native streams already expose stored messages; this is eligibility, not a receipt.
  if (destination.kind === 'native_live') return null;
  const agent = await env.DB.prepare('SELECT name, avatar_url FROM api_keys WHERE id = ?')
    .bind(message.agent_id).first<{ name: string; avatar_url: string | null }>();
  const session = await env.DB.prepare('SELECT label, branch FROM sessions WHERE id = ? AND agent_id = ?')
    .bind(message.session_id, message.agent_id).first<{ label: string | null; branch: string | null }>();
  if (destination.kind === 'apns') return sendApns(env, destination, message, agent?.name ?? 'agent', session);
  const metadata = jsonObject(message.metadata);
  const options = Array.isArray(metadata.options) && metadata.options.every((v): v is string => typeof v === 'string') ? metadata.options : undefined;
  const media = parseOptionMedia(metadata.option_media, options);
  const name = session?.label ? `${session.label} (${agent?.name ?? 'agent'})` : agent?.name ?? 'agent';
  const result = await deliverToChannelWithOptions(
    destination.kind === 'telegram_chat' ? 'telegram' : 'discord', destination.config, name, message.body,
    options?.map(option => [{ text: option, callback_data: `${message.id.slice(0, 12)}:${option}` }]),
    typeof metadata.file_url === 'string' ? metadata.file_url : undefined, agent?.avatar_url ?? undefined,
    env, null, media.ok ? media.value : undefined, options,
  );
  if (!result.delivered) throw new Error('destination adapter did not send');
  return result.telegramMessageId?.toString() ?? result.discordMessageId ?? null;
}

async function sendApns(env: Env, destination: ResolvedDestination, message: MessageRow, agent: string,
  session: { label: string | null; branch: string | null } | null): Promise<null> {
  const device = await env.DB.prepare(`SELECT device_token, bundle_id, environment FROM boss_devices
    WHERE id = ? AND boss_id = ? AND client_id IS ?`)
    .bind(destination.config.device_id, destination.boss_id, destination.client_id)
    .first<{ device_token: string; bundle_id: string; environment: ApnsEnvironment }>();
  if (!device) throw new Error('push device unavailable');
  const preferences = jsonObject(destination.preferences);
  // Destination thresholds own eligibility; retain privacy and presentation preferences.
  const push = typeof preferences.push === 'object' && preferences.push ? preferences.push as Record<string, unknown> : {};
  const tier = typeof push[message.priority] === 'object' && push[message.priority] ? push[message.priority] as Record<string, unknown> : {};
  const prepared = prepareBossPush(message, agent, session, destination.boss_id,
    JSON.stringify({ ...preferences, push: { ...push, [message.priority]: { ...tier, deliver: true } } }));
  if (!prepared) throw new Error('push payload unavailable');
  const result = await sendPush(env, device.device_token, device.environment, device.bundle_id, prepared.payload, prepared.apnsPriority);
  if (result.prune) await env.DB.prepare('DELETE FROM boss_devices WHERE device_token = ?').bind(device.device_token).run();
  if (!result.ok) throw new Error(result.reason);
  return null;
}
