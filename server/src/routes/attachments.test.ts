// Integration tests for /api/attachments endpoints.
// Covers upload (multipart + raw) and download flows.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('POST /api/attachments/upload', () => {
  it('uploads a file via raw binary', async () => {
    const data = new TextEncoder().encode('hello world');
    const res = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: {
        Authorization: authHeaders().Authorization,
        'Content-Type': 'image/png',
        'X-Filename': 'test.txt',
      },
      body: data,
    });
    expect(res.status).toBe(201);
    const json = (await res.json()) as { key: string; url: string; filename: string; content_type: string; size: number };
    expect(json.key).toBeTruthy();
    expect(json.url).toContain('/api/attachments/');
    expect(json.filename).toBe('test.txt');
    expect(json.content_type).toBe('image/png');
    expect(json.size).toBe(11);
  });

  it('accepts raw video/mp4 uploads', async () => {
    const res = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: {
        Authorization: authHeaders().Authorization,
        'Content-Type': 'video/mp4',
        'X-Filename': 'clip.mp4',
      },
      body: new Uint8Array([0, 1, 2]),
    });
    expect(res.status).toBe(201);
    const json = (await res.json()) as { content_type: string; size: number };
    expect(json.content_type).toBe('video/mp4');
    expect(json.size).toBe(3);
  });

  it('rejects unsupported raw content types', async () => {
    const res = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: {
        Authorization: authHeaders().Authorization,
        'Content-Type': 'text/plain',
      },
      body: new TextEncoder().encode('not media'),
    });
    expect(res.status).toBe(400);
  });

  it('rejects empty file', async () => {
    const res = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: {
        Authorization: authHeaders().Authorization,
        'Content-Type': 'image/png',
      },
      body: new ArrayBuffer(0),
    });
    expect(res.status).toBe(400);
  });

  it('rejects unauthenticated upload', async () => {
    const data = new TextEncoder().encode('no auth');
    const res = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: data,
    });
    expect(res.status).toBe(401);
  });
});

describe('GET /api/attachments/:key', () => {
  it('serves uploaded file', async () => {
    const content = 'file content here';
    const data = new TextEncoder().encode(content);
    const uploadRes = await SELF.fetch('https://test.local/api/attachments/upload', {
      method: 'POST',
      headers: {
        Authorization: authHeaders().Authorization,
        'Content-Type': 'image/png',
        'X-Filename': 'serve-test.txt',
      },
      body: data,
    });
    const { key } = (await uploadRes.json()) as { key: string };

    const res = await SELF.fetch(`https://test.local/api/attachments/${key}`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('image/png');
    expect(res.headers.get('content-disposition')).toContain('serve-test.txt');
    const body = await res.text();
    expect(body).toBe(content);
  });

  it('returns 404 for unknown key', async () => {
    const res = await SELF.fetch('https://test.local/api/attachments/nonexistent-key');
    expect(res.status).toBe(404);
  });
});
