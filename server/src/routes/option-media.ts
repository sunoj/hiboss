// Validates option image metadata and returns it in answer-option order.
// Exports parseOptionMedia and its result type for message ingestion/delivery.
// Depends on the shared OptionMedia domain type.

import type { OptionMedia } from '../types';

const MAX_OPTION_MEDIA = 5;

export type OptionMediaParseResult =
  | { ok: true; value: OptionMedia[] | undefined }
  | { ok: false; error: string };

export function parseOptionMedia(value: unknown, options: string[] | undefined): OptionMediaParseResult {
  if (value === undefined) return { ok: true, value: undefined };
  if (!options) return { ok: false, error: 'option_media requires options' };
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_OPTION_MEDIA) {
    return { ok: false, error: 'option_media must contain 1 to 5 valid entries' };
  }
  const seen = new Set<string>();
  const media: OptionMedia[] = [];
  for (const [index, raw] of value.entries()) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      return { ok: false, error: `option_media[${index}] must be an object` };
    }
    const item = raw as Record<string, unknown>;
    const label = typeof item['label'] === 'string' ? item['label'].trim() : '';
    if (!label) return { ok: false, error: `option_media[${index}].label must be a non-empty string` };
    if (seen.has(label)) return { ok: false, error: `option_media label '${label}' must be unique` };
    if (!options.includes(label)) return { ok: false, error: `option_media label '${label}' is not an option` };
    seen.add(label);
    const url = typeof item['url'] === 'string' ? item['url'].trim() : '';
    if (!isHttpUrl(url)) return { ok: false, error: `option_media[${index}].url must be an http(s) URL` };
    if (url.length > 2048) return { ok: false, error: `option_media[${index}].url must be at most 2048 characters` };
    const caption = item['caption'];
    if (caption !== undefined && (typeof caption !== 'string' || caption.length > 200)) {
      return { ok: false, error: `option_media[${index}].caption must be at most 200 characters` };
    }
    media.push({ label, url, ...(caption === undefined ? {} : { caption }) });
  }
  return { ok: true, value: options.flatMap((option) => media.filter((item) => item.label === option)) };
}

function isHttpUrl(value: string): boolean {
  if (!value) return false;
  try {
    const protocol = new URL(value).protocol;
    return protocol === 'http:' || protocol === 'https:';
  } catch {
    return false;
  }
}
