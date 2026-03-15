// Discord adapter that posts messages to a channel via bot REST API.
// Exports a sender helper that accepts channel config and message text.
// Depends on the shared channel config typedefs and global fetch.

import type { DiscordChannelConfig } from '../types';

export async function sendDiscordMessage(config: DiscordChannelConfig, content: string): Promise<void> {
  if (!config.bot_token || !config.channel_id) {
    throw new Error('discord config incomplete');
  }
  const response = await fetch(`https://discord.com/api/v10/channels/${encodeURIComponent(config.channel_id)}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bot ${config.bot_token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ content }),
  });
  if (!response.ok) {
    const payload = await response.text();
    throw new Error(`discord send failed ${response.status} ${payload}`);
  }
}
