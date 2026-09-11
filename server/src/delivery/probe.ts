// Sends explicit destination probes without creating or modifying a message row.
// Exports probeDestination; uses existing channel/APNs adapters and live client checks.
import type { Env } from '../types';
import { deliverToChannelWithOptions } from '../routes/delivery';
import { sendPush, type ApnsEnvironment } from '../apns';
import { jsonObject } from './types';
export interface ProbeDestination { boss_id: string; kind: string; target: string; credentials: string | null; client_id: string | null }
export async function probeDestination(env: Env, row: ProbeDestination): Promise<string | null> {
  const config = { ...jsonObject(row.target), ...jsonObject(row.credentials) };
  if (row.kind === 'native_live') throw new Error('native streams do not support probes');
  if (row.kind === 'apns') {
    const device = await env.DB.prepare(`SELECT d.device_token, d.bundle_id, d.environment FROM boss_devices d
      LEFT JOIN boss_clients c ON c.id = d.client_id WHERE d.id = ? AND d.boss_id = ? AND d.client_id IS ?
      AND (d.client_id IS NULL OR (c.revoked_at IS NULL AND c.boss_id = d.boss_id))`)
      .bind(config.device_id, row.boss_id, row.client_id).first<{ device_token: string; bundle_id: string; environment: ApnsEnvironment }>();
    if (!device) throw new Error('push device unavailable');
    const result = await sendPush(env, device.device_token, device.environment, device.bundle_id,
      { aps: { alert: { title: 'HiBoss', body: 'Test notification' }, sound: 'default', 'interruption-level': 'active', 'thread-id': 'hiboss-test' } }, '10');
    if (!result.ok) throw new Error('push failed');
    return null;
  }
  if (row.kind === 'discord_channel' && config.thread_id && !config.webhook_url) config.channel_id = config.thread_id;
  const result = await deliverToChannelWithOptions(row.kind === 'telegram_chat' ? 'telegram' : 'discord', config, 'HiBoss', 'Test notification');
  if (!result.delivered) throw new Error('probe failed');
  return result.telegramMessageId?.toString() ?? result.discordMessageId ?? null;
}
