// Broadcasts join approval prompts and key-delivery notices to enabled channels.
// Exports notifyJoinRequest and notifyJoinConnected (device + profile names) with target deduplication.
// Depends on D1 channel configs and the Telegram and Discord senders.

import type { DiscordChannelConfig, Env, TelegramChannelConfig } from '../types';
import { sendDiscordMessage } from '../channels/discord';
import { sendTelegramMessage } from '../channels/telegram';

type ChannelConfigRow = {
  channel: 'telegram' | 'discord';
  config: string;
};

type NamedProfile = { profile: string; name: string; agent_id?: string };

export function notifyJoinRequest(env: Env, requestId: string, deviceLabel: string, profiles: NamedProfile[]): Promise<void> {
  return broadcastJoinMessage(env, `Join request from device ${deviceLabel}: ${profileList(profiles)}`, requestId);
}

export function notifyJoinConnected(env: Env, deviceLabel: string, profiles: NamedProfile[]): Promise<void> {
  return broadcastJoinMessage(env, `Device ${deviceLabel} connected — keys delivered for ${profileList(profiles)}`);
}

function profileList(profiles: NamedProfile[]): string {
  return profiles.map(p => `${p.name} (${p.profile})`).join(', ');
}

async function broadcastJoinMessage(env: Env, message: string, requestId?: string): Promise<void> {
  const configs = await env.DB
    .prepare("SELECT DISTINCT channel, config FROM channel_configs WHERE enabled = 1 AND channel IN ('telegram', 'discord')")
    .all<ChannelConfigRow>();
  const sent = new Set<string>();
  for (const row of configs.results ?? []) {
    try {
      const dedupeKey = getChannelDedupeKey(row);
      if (!dedupeKey || sent.has(dedupeKey)) continue;
      sent.add(dedupeKey);
      if (row.channel === 'telegram') {
        await sendTelegramMessage(getTelegramConfig(row.config), message, requestId ? {
          inlineKeyboard: [[
            { text: '✅ Approve', callback_data: `join:approve:${requestId}` },
            { text: '❌ Reject', callback_data: `join:reject:${requestId}` },
          ]],
        } : undefined);
        continue;
      }
      await sendDiscordMessage(getDiscordConfig(row.config), message, requestId ? {
        components: [{
          type: 1,
          components: [
            { type: 2, style: 3, label: 'Approve', custom_id: `join:approve:${requestId}` },
            { type: 2, style: 4, label: 'Reject', custom_id: `join:reject:${requestId}` },
          ],
        }],
      } : undefined);
    } catch {
      // A failed channel must not prevent the other channels from receiving the notice.
    }
  }
}

function getChannelDedupeKey(row: ChannelConfigRow): string | null {
  try {
    const config = JSON.parse(row.config) as Record<string, unknown>;
    const target = row.channel === 'telegram' ? config['chat_id'] : config['channel_id'];
    return typeof target === 'string' && target ? `${row.channel}:${target}` : null;
  } catch {
    return null;
  }
}

function getTelegramConfig(raw: string): TelegramChannelConfig {
  const config = JSON.parse(raw) as Record<string, unknown>;
  if (typeof config['chat_id'] !== 'string' || typeof config['bot_token'] !== 'string') {
    throw new Error('telegram config malformed');
  }
  const telegramConfig: TelegramChannelConfig = { chat_id: config['chat_id'], bot_token: config['bot_token'] };
  if (typeof config['message_thread_id'] === 'number') {
    telegramConfig.message_thread_id = config['message_thread_id'];
  }
  return telegramConfig;
}

function getDiscordConfig(raw: string): DiscordChannelConfig {
  const config = JSON.parse(raw) as Record<string, unknown>;
  if (typeof config['webhook_url'] === 'string') {
    return {
      webhook_url: config['webhook_url'],
      avatar_url: typeof config['avatar_url'] === 'string' ? config['avatar_url'] : undefined,
      bot_token: typeof config['bot_token'] === 'string' ? config['bot_token'] : undefined,
      channel_id: typeof config['channel_id'] === 'string' ? config['channel_id'] : undefined,
    };
  }
  if (typeof config['bot_token'] !== 'string' || typeof config['channel_id'] !== 'string') {
    throw new Error('discord config malformed');
  }
  return { bot_token: config['bot_token'], channel_id: config['channel_id'] };
}
