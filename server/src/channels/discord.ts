// Discord adapter: posts messages via bot API or webhook URL.
// Exports sendDiscordMessage, addDiscordReaction, getDiscordReactions.
// Depends on DiscordChannelConfig from types.

import type { DiscordChannelConfig } from '../types';

interface DiscordAttachment {
  blob: Blob;
  filename: string;
}

interface DiscordAttachmentMetadata {
  id: number;
  filename: string;
}

export interface DiscordEmbed {
  image?: { url: string };
}

export interface DiscordSendOptions {
  username?: string;
  avatarUrl?: string;
  components?: unknown[];
  embeds?: DiscordEmbed[];
  fileUrl?: string;
}

export interface DiscordSendResult {
  messageId?: string;
}

export async function sendDiscordMessage(config: DiscordChannelConfig, content: string, options?: DiscordSendOptions): Promise<DiscordSendResult> {
  if (config.webhook_url) {
    return sendViaWebhook(config.webhook_url, content, options, config.thread_id);
  }
  if (config.bot_token && config.channel_id) {
    return sendViaBot(config.bot_token, config.channel_id, content, options);
  }
  throw new Error('discord config incomplete: need webhook_url or bot_token+channel_id');
}

export async function sendDiscordTyping(config: DiscordChannelConfig): Promise<void> {
  if (!config.bot_token || !config.channel_id) return;
  await fetch(`https://discord.com/api/v10/channels/${encodeURIComponent(config.channel_id)}/typing`, {
    method: 'POST',
    headers: { Authorization: `Bot ${config.bot_token}` },
  });
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

async function sendViaWebhook(webhookUrl: string, content: string, options?: DiscordSendOptions, threadId?: string): Promise<DiscordSendResult> {
  const attachment = options?.fileUrl ? await downloadDiscordAttachment(options.fileUrl) : undefined;
  const payload = buildDiscordPayload(content, options, attachment ? [toAttachmentMetadata(attachment)] : undefined);
  // ?wait=true makes Discord return the created message with its ID
  // thread_id routes the webhook message into a thread
  let url = webhookUrl.includes('?') ? `${webhookUrl}&wait=true` : `${webhookUrl}?wait=true`;
  if (threadId) url += `&thread_id=${encodeURIComponent(threadId)}`;
  const response = await fetch(url, buildDiscordRequest(payload, attachment));
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

async function sendViaBot(botToken: string, channelId: string, content: string, options?: DiscordSendOptions): Promise<DiscordSendResult> {
  const attachment = options?.fileUrl ? await downloadDiscordAttachment(options.fileUrl) : undefined;
  const payload = buildDiscordPayload(content, options, attachment ? [toAttachmentMetadata(attachment)] : undefined);
  const response = await fetch(
    `https://discord.com/api/v10/channels/${encodeURIComponent(channelId)}/messages`,
    buildDiscordRequest(payload, attachment, `Bot ${botToken}`)
  );
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`discord send failed ${response.status} ${body}`);
  }
  const result = await response.json() as Record<string, unknown>;
  return { messageId: typeof result['id'] === 'string' ? result['id'] : undefined };
}

function buildDiscordPayload(
  content: string,
  options?: DiscordSendOptions,
  attachments?: DiscordAttachmentMetadata[],
): Record<string, unknown> {
  const payload: Record<string, unknown> = { content };
  if (options?.username) payload.username = options.username;
  if (options?.avatarUrl) payload.avatar_url = options.avatarUrl;
  if (options?.components) payload.components = options.components;
  if (options?.embeds) payload.embeds = options.embeds;
  if (attachments) payload.attachments = attachments;
  return payload;
}

function buildDiscordRequest(
  payload: Record<string, unknown>,
  attachment?: DiscordAttachment,
  authorization?: string,
): RequestInit {
  const headers: Record<string, string> = {};
  if (authorization) headers.Authorization = authorization;
  if (!attachment) {
    headers['Content-Type'] = 'application/json';
    return { method: 'POST', headers, body: JSON.stringify(payload) };
  }
  const form = new FormData();
  form.set('payload_json', JSON.stringify(payload));
  form.set('files[0]', attachment.blob, attachment.filename);
  return { method: 'POST', headers, body: form };
}

async function downloadDiscordAttachment(fileUrl: string): Promise<DiscordAttachment> {
  const response = await fetch(fileUrl);
  if (!response.ok) {
    throw new Error(`discord attachment download failed ${response.status}`);
  }
  return {
    blob: await response.blob(),
    filename: getDiscordAttachmentFilename(fileUrl, response.headers.get('content-disposition')),
  };
}

function toAttachmentMetadata(attachment: DiscordAttachment): DiscordAttachmentMetadata {
  return { id: 0, filename: attachment.filename };
}

function getDiscordAttachmentFilename(fileUrl: string, contentDisposition: string | null): string {
  const headerName = readContentDispositionFilename(contentDisposition);
  if (headerName) return headerName;
  try {
    const candidate = new URL(fileUrl).pathname.split('/').filter(Boolean).pop();
    if (candidate) return decodeURIComponent(candidate);
  } catch {
    return 'attachment';
  }
  return 'attachment';
}

function readContentDispositionFilename(contentDisposition: string | null): string | undefined {
  if (!contentDisposition) return undefined;
  const utfMatch = contentDisposition.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
  if (utfMatch?.[1]) return decodeURIComponent(utfMatch[1]);
  const quotedMatch = contentDisposition.match(/filename\s*=\s*"([^"]+)"/i);
  if (quotedMatch?.[1]) return quotedMatch[1];
  const plainMatch = contentDisposition.match(/filename\s*=\s*([^;]+)/i);
  return plainMatch?.[1]?.trim();
}
