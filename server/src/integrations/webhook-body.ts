// Reads a Discord webhook request body under a streamed byte cap; files are listed, never stored.
// Exports readWebhookBody (JSON, URL-encoded, multipart with payload_json or fields) and listWebhookFiles.
// Dependencies: the Discord payload parser and the multipart parser.
import { INVALID_BODY, parseDiscordPayload, type DiscordError, type DiscordPayload } from './discord-payload';
import { parseMultipart, type MultipartPart } from './multipart';

const JSON_MAX = 256 * 1024;
/** Files are not stored, so a multipart body only needs room for a few screenshots to be listed. */
const MULTIPART_MAX = 8 * 1024 * 1024;
const TOO_LARGE: DiscordError = { status: 413, code: 40005, message: 'Request entity too large' };

export type WebhookFile = Pick<MultipartPart, 'filename' | 'bytes'>;
export interface WebhookBody { payload: DiscordPayload; files: WebhookFile[] }

/** Counts bytes as they arrive; a missing or false Content-Length cannot exceed the cap. */
async function readCapped(request: Request, max: number): Promise<Uint8Array | null> {
  const declared = Number(request.headers.get('content-length') ?? '0');
  if (declared > max) return null;
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) { await reader.cancel(); return null; }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

function parseJson(text: string): unknown {
  try { return JSON.parse(text); } catch { return undefined; }
}

/** Fields may arrive as individual parts or as one payload_json part; a file part's name is free. */
function formPayload(entries: Iterable<[string, string | WebhookFile]>): { value: unknown; files: WebhookFile[] } {
  const files: WebhookFile[] = [];
  const fields: Record<string, unknown> = {};
  for (const [name, entry] of entries) {
    if (typeof entry !== 'string') { files.push(entry); continue; }
    if (name === 'embeds') fields.embeds = parseJson(entry);
    else if (name === 'flags') fields.flags = Number(entry);
    else fields[name] = entry;
  }
  if (typeof fields.payload_json !== 'string') return { value: fields, files };
  // An explicit payload_json that does not parse is an error, never a fallback to loose fields.
  return { value: parseJson(fields.payload_json) ?? null, files };
}

function formEntries(bytes: Uint8Array, contentType: string): [string, string | WebhookFile][] | null {
  if (contentType.toLowerCase().startsWith('application/x-www-form-urlencoded')) {
    return [...new URLSearchParams(new TextDecoder().decode(bytes)).entries()];
  }
  const parts = parseMultipart(bytes, contentType);
  // Text fields share the JSON cap; only file parts may be large.
  if (parts?.some((part) => part.filename === null && part.bytes.byteLength > JSON_MAX)) return null;
  return parts?.map((part) => [part.name, part.filename === null
    ? new TextDecoder().decode(part.bytes) : { filename: part.filename, bytes: part.bytes }]) ?? null;
}

export async function readWebhookBody(request: Request): Promise<WebhookBody | DiscordError> {
  const type = (request.headers.get('content-type') ?? '').toLowerCase();
  const multipart = type.startsWith('multipart/form-data') || type.startsWith('application/x-www-form-urlencoded');
  const bytes = await readCapped(request, type.startsWith('multipart/form-data') ? MULTIPART_MAX : JSON_MAX);
  if (!bytes) return TOO_LARGE;
  if (!multipart) {
    const value = parseJson(new TextDecoder().decode(bytes));
    if (value === undefined) return INVALID_BODY;
    const payload = parseDiscordPayload(value);
    return 'status' in payload ? payload : { payload, files: [] };
  }
  const entries = formEntries(bytes, request.headers.get('content-type') ?? '');
  if (!entries) return INVALID_BODY;
  const { value, files } = formPayload(entries);
  const payload = parseDiscordPayload(value, files.length > 0);
  return 'status' in payload ? payload : { payload, files };
}

function displayName(file: WebhookFile): string {
  return (file.filename || 'file').replace(/[^\p{L}\p{N} ._-]/gu, '').slice(0, 100) || 'file';
}

/** Files are listed, never stored: a webhook URL must not become a way to host bytes. */
export function listWebhookFiles(files: WebhookFile[]): string[] {
  return files.map((file) => `*attachment not stored: ${displayName(file)} (${file.bytes.byteLength} bytes)*`);
}
