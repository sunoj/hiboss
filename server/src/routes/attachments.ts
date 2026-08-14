// Upload and serve file attachments via R2 storage.
// Exports POST /upload (multipart) and GET /:key (serve file).
// Depends on Hono, auth middleware, R2 bucket binding.

import { Context, Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const TEN_MB = 10 * 1024 * 1024;
const FIFTY_MB = 50 * 1024 * 1024;
const routes = new Hono<{ Bindings: Env }>({});
type AttachmentBody = Parameters<Env['ATTACHMENTS']['put']>[1];

interface AttachmentMetadata {
  httpMetadata: { contentType: string };
  customMetadata: Record<string, string>;
}

function parseContentLength(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}

function isUnknownLengthStreamError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /stream|length/i.test(message);
}

async function putAttachment(
  env: Env,
  key: string,
  body: ArrayBuffer | ReadableStream<Uint8Array>,
  metadata: AttachmentMetadata,
): Promise<void> {
  const uploadBody = body as unknown as AttachmentBody;
  await env.ATTACHMENTS.put(key, uploadBody, metadata);
}

async function putRawAttachment(
  c: Context<{ Bindings: Env }>,
  key: string,
  metadata: AttachmentMetadata,
  maxBytes: number,
): Promise<number> {
  const declaredLength = parseContentLength(c.req.header('content-length'));
  if (declaredLength !== null && declaredLength > maxBytes) return -1;
  if (declaredLength === 0) return 0;
  const stream = c.req.raw.body;
  if (!stream || declaredLength === null) {
    const fileData = await c.req.arrayBuffer();
    if (fileData.byteLength > maxBytes) return -1;
    if (fileData.byteLength > 0) await putAttachment(c.env, key, fileData, metadata);
    return fileData.byteLength;
  }
  try {
    await putAttachment(c.env, key, stream, metadata);
    return declaredLength;
  } catch (error) {
    if (!isUnknownLengthStreamError(error)) throw error;
    const fileData = await c.req.arrayBuffer();
    if (fileData.byteLength > maxBytes) return -1;
    if (fileData.byteLength > 0) await putAttachment(c.env, key, fileData, metadata);
    return fileData.byteLength;
  }
}

routes.post('/upload', apiAuth, async (c) => {
  const agentId = getAgentId(c);
  const contentType = c.req.header('content-type') ?? '';

  let filename: string;
  let mimeType: string;
  let fileData: ArrayBuffer | null = null;
  const isMultipart = contentType.includes('multipart/form-data');

  if (isMultipart) {
    const formData = await c.req.formData();
    const file = formData.get('file');
    if (!file || !(file instanceof File)) {
      return c.text('file field is required', 400);
    }
    fileData = await file.arrayBuffer();
    filename = file.name || 'upload';
    mimeType = file.type || 'application/octet-stream';
  } else {
    filename = c.req.header('x-filename') ?? 'upload';
    mimeType = contentType || 'application/octet-stream';
    if (!mimeType.startsWith('image/') && mimeType !== 'video/mp4') {
      return c.text('raw uploads must be image/* or video/mp4', 400);
    }
  }

  const key = crypto.randomUUID();
  const maxBytes = isMultipart ? TEN_MB : mimeType.startsWith('video/') ? FIFTY_MB : TEN_MB;
  const metadata: AttachmentMetadata = {
    httpMetadata: { contentType: mimeType },
    customMetadata: { agent_id: agentId, filename, uploaded_at: new Date().toISOString() },
  };
  let size: number;
  if (isMultipart) {
    if (!fileData || fileData.byteLength > maxBytes) return c.text('file too large (max 10MB)', 413);
    if (fileData.byteLength === 0) return c.text('empty file', 400);
    await putAttachment(c.env, key, fileData, metadata);
    size = fileData.byteLength;
  } else {
    size = await putRawAttachment(c, key, metadata, maxBytes);
    if (size < 0) return c.text(`file too large (max ${maxBytes / (1024 * 1024)}MB)`, 413);
    if (size === 0) return c.text('empty file', 400);
  }

  const url = new URL(c.req.url);
  const attachmentUrl = `${url.protocol}//${url.host}/api/attachments/${key}`;

  return c.json({ key, url: attachmentUrl, filename, content_type: mimeType, size }, 201);
});

routes.get('/:key', async (c) => {
  const key = c.req.param('key');
  const object = await c.env.ATTACHMENTS.get(key);
  if (!object) {
    return c.text('not found', 404);
  }
  const headers = new Headers();
  headers.set('content-type', object.httpMetadata?.contentType ?? 'application/octet-stream');
  const filename = object.customMetadata?.filename;
  if (filename) {
    headers.set('content-disposition', `inline; filename="${filename}"`);
  }
  headers.set('cache-control', 'public, max-age=31536000, immutable');

  return new Response(object.body as ReadableStream, { headers });
});

export const attachmentsRouter = routes;
