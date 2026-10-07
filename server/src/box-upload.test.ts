// Verifies declared-size rejection before multipart parsing and direct R2 File storage.
// Uses bounded request streams and real Box persistence with Workers D1 and R2.
import { env } from 'cloudflare:test';
import { Hono } from 'hono';
import { beforeAll, expect, it, vi } from 'vitest';
import { OWNER, seedBox } from './box-test-helpers';
import { FILE_BYTES, IMAGE_BYTES, multipartForm } from './box/multipart';
import { createItem } from './box/store';
import type { BoxRow } from './box/types';
import type { Env } from './types';

beforeAll(seedBox);

it('rejects oversized Content-Length without reading or parsing the multipart body', async () => {
  const request = new Request('https://test.local', { method: 'POST', body: 'malformed',
    headers: { 'Content-Type': 'multipart/form-data; boundary=test',
      'Content-Length': String(FILE_BYTES + 64 * 1024 + 1) } });
  const parse = vi.spyOn(request, 'formData');
  await expect(multipartForm(request)).rejects.toMatchObject({ status: 413 });
  expect(request.bodyUsed).toBe(false);
  expect(parse).not.toHaveBeenCalled();
});

it('rejects oversized images from leading part headers before parsing the file', async () => {
  const prefix = '--test\r\nContent-Disposition: form-data; name="file"; filename="image"\r\n'
    + 'Content-Type: image/png\r\n\r\n';
  const request = new Request('https://test.local', { method: 'POST', body: prefix,
    headers: { 'Content-Type': 'multipart/form-data; boundary=test',
      'Content-Length': String(IMAGE_BYTES + 64 * 1024 + 1) } });
  const parse = vi.spyOn(Response.prototype, 'formData');
  try {
    await expect(multipartForm(request)).rejects.toMatchObject({ status: 413 });
    expect(parse).not.toHaveBeenCalled();
  } finally {
    parse.mockRestore();
  }
});

it.each(['video/mp4', 'application/pdf'])(
  'replays split multipart headers and bytes for allowed %s uploads', async type => {
    const parts = ['--test\r\nContent-Disposition: form-data; name="meta"\r\n\r\n{}\r\n',
      '--test\r\nContent-Disposition: form-data; name="fi',
      `le"; filename="reference"\r\nContent-Type: ${type}\r\n\r\n`, 'bytes\r\n--test--\r\n'];
    const request = new Request('https://test.local', { method: 'POST',
      body: new ReadableStream<Uint8Array>({
        start(controller) {
          for (const part of parts) controller.enqueue(new TextEncoder().encode(part));
          controller.close();
        },
      }), headers: { 'Content-Type': 'multipart/form-data; boundary="test"',
        'Content-Length': String(IMAGE_BYTES + 64 * 1024 + 1) } });
    const form = await multipartForm(request);
    expect(form.get('meta')).toBe('{}');
    const file = form.get('file') as File;
    expect(file.type).toBe(type);
    expect(await file.text()).toBe('bytes');
  });

it('bounds the header scan when an oversized multipart request has no file header', async () => {
  const request = new Request('https://test.local', { method: 'POST', body: 'x'.repeat(64 * 1024),
    headers: { 'Content-Type': 'multipart/form-data; boundary=test',
      'Content-Length': String(IMAGE_BYTES + 64 * 1024 + 1) } });
  await expect(multipartForm(request)).rejects.toMatchObject({ status: 413 });
});

it('stores a File in R2 without calling its arrayBuffer method', async () => {
  const app = new Hono<{ Bindings: Env }>();
  const file = new File(['direct bytes'], 'reference', { type: 'image/png' });
  const buffer = vi.spyOn(file, 'arrayBuffer').mockRejectedValue(new Error('extra copy'));
  app.post('/', async c => {
    Object.assign(c, { bossId: OWNER });
    const row = await createItem(c, { file, kind: 'image', meta: {
      text: null, url: null, note: null, project: null, tags: [], source: 'ios-share',
      width: null, height: null, duration_ms: null,
    } }, undefined);
    return c.json(row);
  });
  const response = await app.fetch(new Request('https://test.local/', { method: 'POST' }), env);
  expect(response.status).toBe(200);
  const row = await response.json() as BoxRow;
  expect(buffer).not.toHaveBeenCalled();
  expect(row.media_bytes).toBe(12);
  const stored = await env.ATTACHMENTS.get(row.media_key!);
  expect(await stored?.text()).toBe('direct bytes');
});
