// Renders a parsed Discord webhook payload as a HiBoss title and Markdown details.
// Exports renderDiscordMessage and normalizeDiscordMarkup; no tables, no remote images fetched.
// Dependencies: the payload types from discord-payload.ts.
import type { DiscordEmbed, DiscordPayload } from './discord-payload';

const TITLE_MAX = 144;

function utc(seconds: number): string {
  const date = new Date(seconds * 1000);
  return Number.isNaN(date.getTime()) ? String(seconds)
    : `${date.toISOString().slice(0, 16).replace('T', ' ')} UTC`;
}

/** Discord-only markup (timestamps, mentions, custom emoji, subtext) becomes plain text. */
export function normalizeDiscordMarkup(text: string): string {
  return text
    .replace(/<t:(-?\d{1,12})(?::[tTdDfFR])?>/g, (_, seconds: string) => utc(Number(seconds)))
    .replace(/<@!?\d+>/g, '@user')
    .replace(/<@&\d+>/g, '@role')
    .replace(/<#\d+>/g, '#channel')
    .replace(/<a?:(\w{1,32}):\d+>/g, ':$1:')
    .replace(/^-# /gm, '')
    // Only the server writes cards: a sender's own fence stays code.
    .replace(/^(\s*(?:`{3,}|~{3,})\s*)hiboss-embed/gim, '$1text');
}

function plainLine(text: string): string {
  return normalizeDiscordMarkup(text).split('\n').map((line) => line.trim()).find(Boolean)
    ?.replace(/^#{1,6}\s+/, '').replace(/[*_~`|]/g, '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').trim() ?? '';
}

function clampTitle(text: string): string {
  const chars = Array.from(text);
  return chars.length <= TITLE_MAX ? text : `${chars.slice(0, TITLE_MAX - 1).join('')}…`;
}

function titleOf(payload: DiscordPayload, fallback: string): string {
  const first = payload.embeds[0];
  const candidates = [first?.title, payload.content, first?.description, first?.author];
  for (const candidate of candidates) {
    const line = candidate ? plainLine(candidate) : '';
    if (line) return clampTitle(line);
  }
  return clampTitle(fallback);
}

function embedBlock(embed: DiscordEmbed): string {
  const lines: string[] = [];
  const title = embed.title ? normalizeDiscordMarkup(embed.title).replace(/[[\]]/g, '') : null;
  if (title) lines.push(embed.url ? `**[${title}](${embed.url})**` : `**${title}**`);
  else if (embed.url) lines.push(embed.url);
  if (embed.author) lines.push(`*${normalizeDiscordMarkup(embed.author)}*`);
  if (embed.description) lines.push(normalizeDiscordMarkup(embed.description));
  for (const field of embed.fields) {
    const name = normalizeDiscordMarkup(field.name).replace(/\n/g, ' ');
    const value = normalizeDiscordMarkup(field.value).replace(/\n/g, ' ');
    lines.push(name ? `- **${name}**: ${value}` : `- ${value}`);
  }
  for (const image of [embed.image, embed.thumbnail]) if (image) lines.push(image);
  const footer = [embed.footer && normalizeDiscordMarkup(embed.footer),
    embed.timestamp && `${embed.timestamp.slice(0, 16).replace('T', ' ')} UTC`].filter(Boolean);
  if (footer.length) lines.push(`*${footer.join(' · ')}*`);
  return lines.join('\n');
}

/**
 * rich_content holds only server-written fences, each one line of JSON. Sender text travels inside
 * that JSON, with backticks and every line separator Swift recognizes escaped, so it can neither
 * end a fence nor start one.
 */
function fence(value: object): string {
  const json = JSON.stringify(value).replace(/[`\u0085  ]/g,
    (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, '0')}`);
  return `\`\`\`hiboss-embed\n${json}\n\`\`\``;
}

function embedFence(embed: DiscordEmbed): string {
  const n = (text: string | null) => (text ? normalizeDiscordMarkup(text) : null);
  return fence({
    color: embed.color, title: n(embed.title), url: embed.url, author: n(embed.author),
    description: n(embed.description), image: embed.image, thumbnail: embed.thumbnail,
    fields: embed.fields.map((field) => ({ name: n(field.name) ?? '', value: n(field.value) ?? '',
      inline: field.inline })),
    footer: n(embed.footer), timestamp: embed.timestamp,
  });
}

export interface RenderedMessage { title: string; content: string; richContent: string }

/** The sender stays the integration; a payload `username` is shown as text, never as identity.
 *  `content` is plain Markdown for channels and older apps; `richContent` is what new apps draw. */
export function renderDiscordMessage(payload: DiscordPayload, integrationName: string,
  extraLines: string[] = []): RenderedMessage {
  const lead = payload.content ? normalizeDiscordMarkup(payload.content) : null;
  const notes: string[] = [];
  if (payload.username && payload.username !== integrationName) notes.push(`via ${payload.username}`);
  if (payload.truncated) notes.push('truncated');
  const tail = [...extraLines, ...(notes.length ? [`*${notes.join(' · ')}*`] : [])];
  const plain = payload.embeds.map(embedBlock).filter(Boolean);
  const content = [...(lead ? [lead] : []), ...plain, ...tail].join('\n\n');
  const richContent = [
    ...(lead ? [fence({ text: lead })] : []),
    ...payload.embeds.map(embedFence),
    ...(tail.length ? [fence({ text: tail.join('\n\n') })] : []),
  ].join('\n\n');
  return { title: titleOf(payload, integrationName), content, richContent };
}
