// Parses the Discord Execute Webhook body leniently: unknown fields are ignored, long values clamped.
// Exports DiscordPayload, parseDiscordPayload and the Discord error shape used by the route.
// Dependencies: none; rendering into a HiBoss title and Markdown lives in discord-render.ts.

export interface DiscordEmbedField { name: string; value: string }
export interface DiscordEmbed {
  title: string | null; url: string | null; description: string | null; author: string | null;
  fields: DiscordEmbedField[]; image: string | null; thumbnail: string | null;
  footer: string | null; timestamp: string | null;
}
export interface DiscordPayload {
  content: string | null; username: string | null; embeds: DiscordEmbed[]; flags: number;
  truncated: boolean; threadName: string | null;
}
export interface DiscordError { status: 400 | 404 | 405 | 413 | 429; code: number; message: string }

/** Discord's own limits; HiBoss clamps instead of rejecting, so an alert is never lost to a 400. */
const LIMITS = { content: 2000, embeds: 10, fields: 25, title: 256, description: 4096, fieldName: 256,
  fieldValue: 1024, footer: 2048, author: 256, embedTotal: 6000 } as const;
export const SUPPRESS_NOTIFICATIONS = 1 << 12;
const COMPONENTS_V2 = 1 << 15;

export const EMPTY_MESSAGE: DiscordError = { status: 400, code: 50006, message: 'Cannot send an empty message' };
export const INVALID_BODY: DiscordError = { status: 400, code: 50035, message: 'Invalid Form Body' };

type Record_ = Record<string, unknown>;
const isRecord = (value: unknown): value is Record_ => typeof value === 'object' && value !== null && !Array.isArray(value);

class Clamp {
  truncated = false;
  embedChars = 0;
  text(value: unknown, max: number, embed = false): string | null {
    if (typeof value !== 'string' || !value.trim()) return null;
    const room = embed ? Math.max(0, LIMITS.embedTotal - this.embedChars) : max;
    const limit = Math.min(max, room);
    const chars = Array.from(value);
    if (chars.length > limit) this.truncated = true;
    const kept = chars.slice(0, limit).join('');
    if (embed) this.embedChars += Array.from(kept).length;
    return kept || null;
  }
  url(value: unknown): string | null {
    const text = isRecord(value) ? value.url : value;
    if (typeof text !== 'string') return null;
    try {
      const url = new URL(text);
      return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : null;
    } catch { return null; }
  }
}

function parseEmbed(value: Record_, clamp: Clamp): DiscordEmbed {
  const rawFields = Array.isArray(value.fields) ? value.fields.filter(isRecord) : [];
  if (rawFields.length > LIMITS.fields) clamp.truncated = true;
  const fields = rawFields.slice(0, LIMITS.fields).flatMap((field) => {
    const name = clamp.text(field.name, LIMITS.fieldName, true);
    const fieldValue = clamp.text(field.value, LIMITS.fieldValue, true);
    return name || fieldValue ? [{ name: name ?? '', value: fieldValue ?? '' }] : [];
  });
  return {
    title: clamp.text(value.title, LIMITS.title, true),
    url: clamp.url(value.url),
    description: clamp.text(value.description, LIMITS.description, true),
    author: isRecord(value.author) ? clamp.text(value.author.name, LIMITS.author, true) : null,
    fields,
    image: clamp.url(value.image),
    thumbnail: clamp.url(value.thumbnail),
    footer: isRecord(value.footer) ? clamp.text(value.footer.text, LIMITS.footer, true) : null,
    timestamp: typeof value.timestamp === 'string' && !Number.isNaN(Date.parse(value.timestamp))
      ? new Date(value.timestamp).toISOString() : null,
  };
}

/** `hasFiles` lets a multipart post with only an attachment pass the empty-message check. */
export function parseDiscordPayload(value: unknown, hasFiles = false): DiscordPayload | DiscordError {
  if (!isRecord(value)) return INVALID_BODY;
  const flags = typeof value.flags === 'number' && Number.isInteger(value.flags) ? value.flags : 0;
  if (flags & COMPONENTS_V2) return { ...INVALID_BODY, message: 'Components V2 messages are not supported' };
  const clamp = new Clamp();
  const rawEmbeds = Array.isArray(value.embeds) ? value.embeds.filter(isRecord) : [];
  if (rawEmbeds.length > LIMITS.embeds) clamp.truncated = true;
  const embeds = rawEmbeds.slice(0, LIMITS.embeds).map((embed) => parseEmbed(embed, clamp))
    .filter((embed) => embed.title || embed.description || embed.fields.length || embed.image
      || embed.author || embed.footer || embed.url || embed.thumbnail);
  const content = clamp.text(value.content, LIMITS.content);
  if (!content && embeds.length === 0 && !hasFiles) return EMPTY_MESSAGE;
  return {
    content, embeds, flags, truncated: clamp.truncated,
    username: clamp.text(value.username, 80),
    threadName: clamp.text(value.thread_name, 100),
  };
}
