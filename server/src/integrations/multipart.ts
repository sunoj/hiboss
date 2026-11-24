// Strict multipart/form-data parser for webhook senders the runtime parser rejects.
// Exports parseMultipart; Grafana names its file parts with an empty string, which workerd refuses.
// Dependencies: none; the caller authenticates and caps the body before calling it.

export interface MultipartPart { name: string; filename: string | null; type: string; bytes: Uint8Array }

const MAX_PARTS = 20;
const MAX_HEADER_BYTES = 8 * 1024;

/** RFC 2046: 1–70 characters from a fixed set, so a hostile boundary cannot inflate the search. */
function boundaryOf(contentType: string): string | null {
  const match = contentType.match(/boundary=(?:"([^"]+)"|([^;\s]+))/i);
  const boundary = match ? (match[1] ?? match[2]) : null;
  return boundary && /^[0-9A-Za-z'()+_,\-./:=? ]{1,70}$/.test(boundary) ? boundary : null;
}

function headerParam(header: string, key: string): string | null {
  const match = header.match(new RegExp(`(?:^|;)\\s*${key}="([^"]*)"`, 'i'))
    ?? header.match(new RegExp(`(?:^|;)\\s*${key}=([^;]*)`, 'i'));
  return match ? match[1].trim() : null;
}

function parsePart(text: string, body: Uint8Array, start: number, end: number, shift: number): MultipartPart | null {
  const split = text.indexOf('\r\n\r\n', start);
  if (split < 0 || split > end || split - start > MAX_HEADER_BYTES) return null;
  const headers = text.slice(start, split).split('\r\n');
  const disposition = headers.find((line) => /^content-disposition:/i.test(line)) ?? '';
  if (!/^content-disposition:\s*form-data/i.test(disposition)) return null;
  const type = headers.find((line) => /^content-type:/i.test(line))?.split(':')[1]?.trim() ?? 'text/plain';
  return { name: headerParam(disposition, 'name') ?? '', filename: headerParam(disposition, 'filename'),
    type, bytes: body.subarray(split + 4 - shift, end - shift) };
}

/** One UTF-16 unit per byte, so string offsets are byte offsets. */
function byteString(bytes: Uint8Array): string {
  let text = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    text += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return text;
}

/**
 * A delimiter counts only as a whole line ("\r\n--boundary" followed by "\r\n" or the closing "--"),
 * so file bytes that merely contain the boundary text never split a part. The body is read as
 * one character per byte, so the engine's native substring search does the scanning.
 * Returns null for anything that is not well-formed multipart.
 */
type Delimiter = { at: number; close: boolean };

/** The next real delimiter line at or after `from`; a boundary-like string inside data is skipped. */
function nextDelimiter(text: string, delimiter: string, from: number): Delimiter | null {
  for (let at = text.indexOf(delimiter, from); at >= 0; at = text.indexOf(delimiter, at + 1)) {
    const after = at + delimiter.length;
    if (text.startsWith('\r\n', after)) return { at, close: false };
    // A close delimiter may carry transport padding before its line break or the end of the body.
    const rest = /^--[ \t]*(\r\n|$)/.exec(text.slice(after, after + 64));
    if (rest) return { at, close: true };
  }
  return null;
}

export function parseMultipart(body: Uint8Array, contentType: string): MultipartPart[] | null {
  const boundary = boundaryOf(contentType);
  if (!boundary) return null;
  // The first delimiter may open the body without a preceding line break.
  const text = `\r\n${byteString(body)}`;
  const delimiter = `\r\n--${boundary}`;
  let current = nextDelimiter(text, delimiter, 0);
  const parts: MultipartPart[] = [];
  while (current && !current.close) {
    if (parts.length >= MAX_PARTS) return null;
    const start = current.at + delimiter.length + 2;
    const next = nextDelimiter(text, delimiter, start);
    if (!next) return null;
    // Offsets in `text` are one ahead of the body because of the leading line break.
    const part = parsePart(text, body, start, next.at, 2);
    if (!part) return null;
    parts.push(part);
    current = next;
  }
  return current ? parts : null;
}
