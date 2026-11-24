// Strict multipart/form-data parser for webhook senders the runtime parser rejects.
// Exports parseMultipart; Grafana names its file parts with an empty string, which workerd refuses.
// Dependencies: none; the caller authenticates and caps the body before calling it.

export interface MultipartPart { name: string; filename: string | null; type: string; bytes: Uint8Array }

const MAX_PARTS = 20;
const MAX_HEADER_BYTES = 8 * 1024;

/** Media-type parameters (RFC 2045): quoted values may contain ';' and backslash-escaped characters. */
function parameters(contentType: string): Map<string, string> {
  const result = new Map<string, string>();
  const pattern = /;\s*([!#$%&'*+.^_`|~0-9A-Za-z-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;\s"]*))/g;
  for (const match of contentType.matchAll(pattern)) {
    const name = match[1].toLowerCase();
    if (!result.has(name)) result.set(name, match[2]?.replace(/\\(.)/g, '$1') ?? match[3] ?? '');
  }
  return result;
}

/** The exact `boundary` parameter of the media type (RFC 2046: 1–70 characters from a fixed set). */
function boundaryOf(contentType: string): string | null {
  const value = parameters(contentType).get('boundary') ?? '';
  return /^[0-9A-Za-z'()+_,\-./:=? ]{0,69}[0-9A-Za-z'()+_,\-./:=?]$/.test(value) ? value : null;
}

function headerParam(header: string, key: string): string | null {
  const match = header.match(new RegExp(`(?:^|;)\\s*${key}="([^"]*)"`, 'i'))
    ?? header.match(new RegExp(`(?:^|;)\\s*${key}=([^;]*)`, 'i'));
  return match ? match[1].trim() : null;
}

/** One UTF-16 unit per byte, so string offsets are byte offsets. */
function byteString(bytes: Uint8Array): string {
  let text = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    text += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return text;
}

/** Headers end with a blank line that must sit wholly inside the part; they are UTF-8 text. */
function parsePart(text: string, body: Uint8Array, start: number, end: number): MultipartPart | null {
  const split = text.slice(start, Math.min(end, start + MAX_HEADER_BYTES + 4)).indexOf('\r\n\r\n');
  if (split < 0 || start + split + 4 > end) return null;
  const headers = new TextDecoder().decode(body.subarray(start, start + split)).split('\r\n');
  const disposition = headers.find((line) => /^content-disposition:/i.test(line)) ?? '';
  if (!/^content-disposition:\s*form-data/i.test(disposition)) return null;
  const type = headers.find((line) => /^content-type:/i.test(line))?.split(':')[1]?.trim() ?? 'text/plain';
  return { name: headerParam(disposition, 'name') ?? '', filename: headerParam(disposition, 'filename'),
    type, bytes: body.subarray(start + split + 4, end) };
}

type Delimiter = { at: number; close: boolean; next: number };

/**
 * The next real delimiter line at or after `from`: "--boundary" at the start of a line, optional
 * transport padding, then a line break (or, for the closing "--boundary--", the end of the body).
 * Anything else that merely contains the boundary text is data and is skipped.
 */
function nextDelimiter(text: string, boundary: string, from: number): Delimiter | null {
  const marker = `--${boundary}`;
  for (let at = text.indexOf(marker, from); at >= 0; at = text.indexOf(marker, at + 1)) {
    if (at !== 0 && !text.startsWith('\r\n', at - 2)) continue;
    let index = at + marker.length;
    const close = text.startsWith('--', index);
    if (close) index += 2;
    while (text[index] === ' ' || text[index] === '\t') index += 1;
    if (text.startsWith('\r\n', index)) return { at, close, next: index + 2 };
    if (close && index === text.length) return { at, close, next: index };
  }
  return null;
}

/**
 * Parts sit between delimiter lines; the line break before a delimiter belongs to it. The body
 * is read one character per byte so the engine's native substring search does the scanning.
 * Returns null for anything that is not well-formed multipart.
 */
export function parseMultipart(body: Uint8Array, contentType: string): MultipartPart[] | null {
  const boundary = boundaryOf(contentType);
  if (!boundary) return null;
  const text = byteString(body);
  let current = nextDelimiter(text, boundary, 0);
  const parts: MultipartPart[] = [];
  while (current && !current.close) {
    if (parts.length >= MAX_PARTS) return null;
    const next = nextDelimiter(text, boundary, current.next);
    if (!next || next.at < current.next + 2) return null;
    const part = parsePart(text, body, current.next, next.at - 2);
    if (!part) return null;
    parts.push(part);
    current = next;
  }
  return current ? parts : null;
}
