// Discord adapter: posts messages via bot API or webhook URL.
// Exports sendDiscordMessage, addDiscordReaction, getDiscordReactions.
// Depends on DiscordChannelConfig from types.

import type { DiscordChannelConfig } from '../types';

export interface DiscordSendOptions {
  username?: string;
  avatarUrl?: string;
  components?: unknown[];
}

export interface DiscordSendResult {
  messageId?: string;
}

export async function sendDiscordMessage(config: DiscordChannelConfig, content: string, options?: DiscordSendOptions): Promise<DiscordSendResult> {
  if (config.webhook_url) {
    return sendViaWebhook(config.webhook_url, content, options);
  }
  if (config.bot_token && config.channel_id) {
    return sendViaBot(config.bot_token, config.channel_id, content, options?.components);
  }
  throw new Error('discord config incomplete: need webhook_url or bot_token+channel_id');
}

export async function addDiscordReaction(botToken: string, channelId: string, messageId: string, emoji: string): Promise<void> {
  const encoded = encodeURIComponent(emoji);
  const response = await fetch(
    `https://discord.com/api/v10/channels/${encodeURIComponent(channelId)}/messages/${encodeURIComponent(messageId)}/reactions/${encoded}/@me`,
    { method: 'PUT', headers: { Authorization: `Bot ${botToken}` } }
  );
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`discord reaction failed ${response.status} ${body}`);
  }
}

export async function getDiscordReactions(botToken: string, channelId: string, messageId: string): Promise<{ emoji: string; count: number }[]> {
  const response = await fetch(
    `https://discord.com/api/v10/channels/${encodeURIComponent(channelId)}/messages/${encodeURIComponent(messageId)}`,
    { method: 'GET', headers: { Authorization: `Bot ${botToken}` } }
  );
  if (!response.ok) return [];
  const msg = await response.json() as Record<string, unknown>;
  const reactions = msg['reactions'] as { emoji: { name: string }; count: number }[] | undefined;
  if (!Array.isArray(reactions)) return [];
  return reactions.map((r) => ({ emoji: r.emoji.name, count: r.count }));
}

export async function createDiscordThread(botToken: string, channelId: string, messageId: string, name: string): Promise<string> {
  const response = await fetch(
    `https://discord.com/api/v10/channels/${encodeURIComponent(channelId)}/messages/${encodeURIComponent(messageId)}/threads`,
    {
      method: 'POST',
      headers: { Authorization: `Bot ${botToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: name.slice(0, 100), auto_archive_duration: 1440 }),
    }
  );
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`discord thread creation failed ${response.status} ${body}`);
  }
  const result = await response.json() as Record<string, unknown>;
  const threadId = result['id'];
  if (typeof threadId !== 'string') throw new Error('discord thread creation returned no id');
  return threadId;
}

async function sendViaWebhook(webhookUrl: string, content: string, options?: DiscordSendOptions): Promise<DiscordSendResult> {
  const payload: Record<string, unknown> = { content };
  if (options?.username) payload.username = options.username;
  if (options?.avatarUrl) payload.avatar_url = options.avatarUrl;
  if (options?.components) payload.components = options.components;
  // ?wait=true makes Discord return the created message with its ID
  const url = webhookUrl.includes('?') ? `${webhookUrl}&wait=true` : `${webhookUrl}?wait=true`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`discord webhook failed ${response.status} ${body}`);
  }
  const result = await response.json() as Record<string, unknown>;
  return { messageId: typeof result['id'] === 'string' ? result['id'] : undefined };
}

export async function editDiscordMessage(config: DiscordChannelConfig, messageId: string, content: string, components?: unknown[]): Promise<void> {
  if (config.webhook_url) {
    const url = `${config.webhook_url}/messages/${encodeURIComponent(messageId)}`;
    const payload: Record<string, unknown> = { content, components: components ?? [] };
    await fetch(url, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    return;
  }
  if (config.bot_token && config.channel_id) {
    const payload: Record<string, unknown> = { content, components: components ?? [] };
    await fetch(`https://discord.com/api/v10/channels/${encodeURIComponent(config.channel_id)}/messages/${encodeURIComponent(messageId)}`, {
      method: 'PATCH',
      headers: { Authorization: `Bot ${config.bot_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return;
  }
}

async function sendViaBot(botToken: string, channelId: string, content: string, components?: unknown[]): Promise<DiscordSendResult> {
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
  const result = await response.json() as Record<string, unknown>;
  return { messageId: typeof result['id'] === 'string' ? result['id'] : undefined };
}
