// Minimal binary-safe multipart/form-data parser for webhook senders the runtime parser rejects.
// Exports parseMultipart; Grafana names its file parts with an empty string, which workerd refuses.
// Dependencies: none; the caller has already capped the body size.

export interface MultipartPart { name: string; filename: string | null; type: string; bytes: Uint8Array }

function boundaryOf(contentType: string): string | null {
  const match = contentType.match(/boundary=(?:"([^"]+)"|([^;\s]+))/i);
  return match ? (match[1] ?? match[2]) : null;
}

function indexOf(haystack: Uint8Array, needle: Uint8Array, from: number): number {
  outer: for (let i = from; i <= haystack.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) if (haystack[i + j] !== needle[j]) continue outer;
    return i;
  }
  return -1;
}

function headerParam(header: string, key: string): string | null {
  const match = header.match(new RegExp(`(?:^|;)\\s*${key}="([^"]*)"`, 'i'))
    ?? header.match(new RegExp(`(?:^|;)\\s*${key}=([^;]*)`, 'i'));
  return match ? match[1].trim() : null;
}

function parsePart(bytes: Uint8Array): MultipartPart | null {
  const split = indexOf(bytes, new TextEncoder().encode('\r\n\r\n'), 0);
  if (split < 0) return null;
  const headers = new TextDecoder().decode(bytes.subarray(0, split)).split('\r\n');
  const disposition = headers.find((line) => /^content-disposition:/i.test(line)) ?? '';
  const type = headers.find((line) => /^content-type:/i.test(line))?.split(':')[1]?.trim() ?? 'text/plain';
  return { name: headerParam(disposition, 'name') ?? '', filename: headerParam(disposition, 'filename'),
    type, bytes: bytes.subarray(split + 4) };
}

/** Returns null when the body is not well-formed multipart for the declared boundary. */
export function parseMultipart(body: Uint8Array, contentType: string): MultipartPart[] | null {
  const boundary = boundaryOf(contentType);
  if (!boundary) return null;
  const delimiter = new TextEncoder().encode(`--${boundary}`);
  const parts: MultipartPart[] = [];
  let start = indexOf(body, delimiter, 0);
  if (start < 0) return null;
  for (;;) {
    const contentStart = start + delimiter.length;
    if (body[contentStart] === 0x2d && body[contentStart + 1] === 0x2d) return parts;
    const next = indexOf(body, delimiter, contentStart);
    if (next < 0) return null;
    // Each part sits between "\r\n" after the delimiter and "\r\n" before the next one.
    const part = parsePart(body.subarray(contentStart + 2, next - 2));
    if (!part) return null;
    parts.push(part);
    start = next;
  }
}
