// Discord adapter: posts messages via bot API or webhook URL.
// Exports sendDiscordMessage which auto-detects config mode.
// Depends on DiscordChannelConfig from types.

import type { DiscordChannelConfig } from '../types';

export interface DiscordSendOptions {
  username?: string;
  avatarUrl?: string;
  components?: unknown[];
}

export async function sendDiscordMessage(config: DiscordChannelConfig, content: string, options?: DiscordSendOptions): Promise<void> {
  if (config.webhook_url) {
    return sendViaWebhook(config.webhook_url, content, options);
  }
  if (config.bot_token && config.channel_id) {
    return sendViaBot(config.bot_token, config.channel_id, content, options?.components);
  }
  throw new Error('discord config incomplete: need webhook_url or bot_token+channel_id');
}

async function sendViaWebhook(webhookUrl: string, content: string, options?: DiscordSendOptions): Promise<void> {
  const payload: Record<string, unknown> = { content };
  if (options?.username) payload.username = options.username;
  if (options?.avatarUrl) payload.avatar_url = options.avatarUrl;
  if (options?.components) payload.components = options.components;
  const response = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`discord webhook failed ${response.status} ${body}`);
  }
}

async function sendViaBot(botToken: string, channelId: string, content: string, components?: unknown[]): Promise<void> {
  const payload: Record<string, unknown> = { content };
  if (components) payload.components = components;
  const response = await fetch(`https://discord.com/api/v10/channels/${encodeURIComponent(channelId)}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bot ${botToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`discord send failed ${response.status} ${body}`);
  }
}
