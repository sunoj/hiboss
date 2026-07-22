// Sparkle auto-update feed + signed build hosting for the macOS client.
// Exports updatesRouter mounted at /updates.
//   GET  /updates/macos/appcast.xml   -> public feed, served from R2 (short cache).
//   GET  /updates/macos/:file         -> public signed .zip build, immutable cache.
//   PUT  /updates/macos/:file         -> publish (Bearer RELEASE_UPLOAD_SECRET).
// Sparkle fetches GET without auth and verifies each build's EdDSA signature;
// integrity comes from the signature, so the artifacts are intentionally public.
// Depends on Hono, the R2 bucket binding, and timingSafeEqual.

import { Hono } from 'hono';
import type { Env } from '../types';
import { timingSafeEqual } from '../middleware/auth';

const routes = new Hono<{ Bindings: Env }>({});

const PREFIX = 'updates/macos/';
const SAFE_NAME = /^[A-Za-z0-9._-]+$/;
const MAX_UPLOAD = 500 * 1024 * 1024; // 500 MB — a signed .app zip, not user content.

function objectKey(file: string): string | null {
  if (!SAFE_NAME.test(file) || file.includes('..')) return null;
  return PREFIX + file;
}

function contentTypeFor(file: string): string {
  if (file.endsWith('.xml')) return 'application/xml';
  if (file.endsWith('.zip')) return 'application/zip';
  return 'application/octet-stream';
}

routes.get('/macos/:file', async (c) => {
  const file = c.req.param('file');
  const key = objectKey(file);
  if (!key) return c.text('invalid name', 400);

  const object = await c.env.ATTACHMENTS.get(key);
  if (!object) return c.text('not found', 404);

  const headers = new Headers();
  headers.set('content-type', object.httpMetadata?.contentType ?? contentTypeFor(file));
  // Feed must refresh; immutable signed builds can cache hard.
  headers.set(
    'cache-control',
    file.endsWith('.xml') ? 'public, max-age=300' : 'public, max-age=31536000, immutable',
  );
  return new Response(object.body as ReadableStream, { headers });
});

routes.put('/macos/:file', async (c) => {
  const secret = c.env.RELEASE_UPLOAD_SECRET;
  if (!secret) return c.text('uploads not configured', 500);
  const auth = c.req.header('authorization') ?? '';
  const bearer = auth.startsWith('Bearer ') ? auth.slice('Bearer '.length) : '';
  if (!bearer || !timingSafeEqual(bearer, secret)) return c.text('forbidden', 403);

  const file = c.req.param('file');
  const key = objectKey(file);
  if (!key) return c.text('invalid name', 400);

  const body = await c.req.arrayBuffer();
  if (body.byteLength === 0) return c.text('empty body', 400);
  if (body.byteLength > MAX_UPLOAD) return c.text('too large', 413);

  await c.env.ATTACHMENTS.put(key, body, {
    httpMetadata: { contentType: c.req.header('content-type') || contentTypeFor(file) },
  });
  return c.json({ published: file, size: body.byteLength }, 201);
});

export const updatesRouter = routes;
