// Upload and serve file attachments via R2 storage.
// Exports POST /upload (multipart) and GET /:key (serve file).
// Depends on Hono, auth middleware, R2 bucket binding.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const routes = new Hono<{ Bindings: Env }>({});

routes.post('/upload', apiAuth, async (c) => {
  const agentId = getAgentId(c);
  const contentType = c.req.header('content-type') ?? '';

  let fileData: ArrayBuffer;
  let filename: string;
  let mimeType: string;

  if (contentType.includes('multipart/form-data')) {
    const formData = await c.req.formData();
    const file = formData.get('file');
    if (!file || !(file instanceof File)) {
      return c.text('file field is required', 400);
    }
    fileData = await file.arrayBuffer();
    filename = file.name || 'upload';
    mimeType = file.type || 'application/octet-stream';
  } else {
    // Raw binary upload with headers
    fileData = await c.req.arrayBuffer();
    filename = c.req.header('x-filename') ?? 'upload';
    mimeType = contentType || 'application/octet-stream';
  }

  if (fileData.byteLength === 0) {
    return c.text('empty file', 400);
  }
  if (fileData.byteLength > 10 * 1024 * 1024) {
    return c.text('file too large (max 10MB)', 413);
  }

  const key = crypto.randomUUID();
  await c.env.ATTACHMENTS.put(key, fileData, {
    httpMetadata: { contentType: mimeType },
    customMetadata: { agent_id: agentId, filename, uploaded_at: new Date().toISOString() },
  });

  const url = new URL(c.req.url);
  const attachmentUrl = `${url.protocol}//${url.host}/api/attachments/${key}`;

  return c.json({ key, url: attachmentUrl, filename, content_type: mimeType, size: fileData.byteLength }, 201);
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
