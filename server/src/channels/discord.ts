// Discord adapter: posts messages via bot API or webhook URL.
// Exports sendDiscordMessage which auto-detects config mode.
// Depends on DiscordChannelConfig from types.

import type { DiscordChannelConfig } from '../types';

export async function sendDiscordMessage(config: DiscordChannelConfig, content: string): Promise<void> {
  if (config.webhook_url) {
    return sendViaWebhook(config.webhook_url, content);
  }
  if (config.bot_token && config.channel_id) {
    return sendViaBot(config.bot_token, config.channel_id, content);
  }
  throw new Error('discord config incomplete: need webhook_url or bot_token+channel_id');
}

async function sendViaWebhook(webhookUrl: string, content: string): Promise<void> {
  const response = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content }),
  });
  if (!response.ok) {
    const payload = await response.text();
    throw new Error(`discord webhook failed ${response.status} ${payload}`);
  }
}

async function sendViaBot(botToken: string, channelId: string, content: string): Promise<void> {
  const response = await fetch(`https://discord.com/api/v10/channels/${encodeURIComponent(channelId)}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bot ${botToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ content }),
  });
  if (!response.ok) {
    const payload = await response.text();
    throw new Error(`discord send failed ${response.status} ${payload}`);
  }
}
