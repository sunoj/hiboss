// Reads a Discord webhook request body under a streamed byte cap, then stores its images after auth.
// Exports readWebhookBody (JSON, multipart with payload_json or fields) and storeWebhookFiles.
// Dependencies: the Discord payload parser and the ATTACHMENTS R2 bucket; only images are kept.
import type { Env } from '../types';
import { INVALID_BODY, parseDiscordPayload, type DiscordError, type DiscordPayload } from './discord-payload';
import { parseMultipart, type MultipartPart } from './multipart';

const JSON_MAX = 256 * 1024;
const FILE_MAX = 10 * 1024 * 1024;
const MAX_FILES = 4;
const MULTIPART_MAX = MAX_FILES * FILE_MAX + JSON_MAX;
const TOO_LARGE: DiscordError = { status: 413, code: 40005, message: 'Request entity too large' };

export type WebhookFile = Pick<MultipartPart, 'filename' | 'bytes'>;
export interface WebhookBody { payload: DiscordPayload; files: WebhookFile[] }
export interface StoredFiles { fileUrl: string | undefined; fileLines: string[] }

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
  const json = typeof fields.payload_json === 'string' ? parseJson(fields.payload_json) : undefined;
  return { value: json ?? fields, files };
}

function formEntries(bytes: Uint8Array, contentType: string): [string, string | WebhookFile][] | null {
  if (contentType.toLowerCase().startsWith('application/x-www-form-urlencoded')) {
    return [...new URLSearchParams(new TextDecoder().decode(bytes)).entries()];
  }
  const parts = parseMultipart(bytes, contentType);
  return parts?.map((part) => [part.name, part.filename === null
    ? new TextDecoder().decode(part.bytes) : { filename: part.filename, bytes: part.bytes }]) ?? null;
}

export async function readWebhookBody(request: Request): Promise<WebhookBody | DiscordError> {
  const type = (request.headers.get('content-type') ?? '').toLowerCase();
  const multipart = type.startsWith('multipart/form-data') || type.startsWith('application/x-www-form-urlencoded');
  const bytes = await readCapped(request, multipart ? MULTIPART_MAX : JSON_MAX);
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

const SIGNATURES: [string, string, (bytes: Uint8Array) => boolean][] = [
  ['image/png', 'png', (b) => b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47],
  ['image/jpeg', 'jpg', (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff],
  ['image/gif', 'gif', (b) => b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46],
  ['image/webp', 'webp', (b) => b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57 && b[9] === 0x45],
];

function displayName(file: WebhookFile): string {
  return (file.filename || 'file').replace(/[\r\n[\]()]/g, '').slice(0, 100);
}

/** Runs after authentication: images become attachments, anything else is only listed by name. */
export async function storeWebhookFiles(env: Env, files: WebhookFile[], requestUrl: string,
  agentId: string): Promise<StoredFiles> {
  const urls: string[] = [];
  const lines: string[] = [];
  for (const file of files) {
    const { bytes } = file;
    const kind = SIGNATURES.find(([, , matches]) => matches(bytes));
    if (!kind || bytes.byteLength > FILE_MAX || urls.length >= MAX_FILES) {
      lines.push(`*file not stored: ${displayName(file)} (${bytes.byteLength} bytes)*`);
      continue;
    }
    const key = `${crypto.randomUUID()}.${kind[1]}`;
    await env.ATTACHMENTS.put(key, bytes, { httpMetadata: { contentType: kind[0] },
      customMetadata: { agent_id: agentId, filename: displayName(file), uploaded_at: new Date().toISOString() } });
    const url = new URL(`/api/attachments/${key}`, requestUrl).toString();
    if (urls.length > 0) lines.push(`[${displayName(file)}](${url})`);
    urls.push(url);
  }
  return { fileUrl: urls[0], fileLines: lines };
}
