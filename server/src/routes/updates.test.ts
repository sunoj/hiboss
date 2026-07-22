// Integration tests for the macOS Sparkle update feed + release upload.
// Covers public GET serving, path-traversal rejection, and Bearer-gated PUT.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, afterAll } from 'vitest';

const BASE = 'https://test.local/updates/macos';
const SECRET = 'release-secret';

afterAll(() => {
  env.RELEASE_UPLOAD_SECRET = undefined;
});

describe('GET /updates/macos/:file', () => {
  it('serves a stored appcast with an xml content-type and a short cache', async () => {
    await env.ATTACHMENTS.put('updates/macos/appcast.xml', '<rss></rss>', {
      httpMetadata: { contentType: 'application/xml' },
    });
    const res = await SELF.fetch(`${BASE}/appcast.xml`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('application/xml');
    expect(res.headers.get('cache-control')).toBe('public, max-age=300');
  });

  it('returns 404 for a missing object', async () => {
    const res = await SELF.fetch(`${BASE}/nope.zip`);
    expect(res.status).toBe(404);
  });

  it('rejects path-traversal / unsafe names with 400', async () => {
    const res = await SELF.fetch(`${BASE}/..%2F..%2Fsecret`);
    expect(res.status).toBe(400);
  });
});

describe('PUT /updates/macos/:file', () => {
  it('rejects uploads without the correct bearer secret', async () => {
    env.RELEASE_UPLOAD_SECRET = SECRET;
    const res = await SELF.fetch(`${BASE}/hiboss-1.0.0.zip`, {
      method: 'PUT',
      headers: { Authorization: 'Bearer wrong', 'content-type': 'application/zip' },
      body: 'zipbytes',
    });
    expect(res.status).toBe(403);
  });

  it('publishes with the correct secret and serves it back', async () => {
    env.RELEASE_UPLOAD_SECRET = SECRET;
    const put = await SELF.fetch(`${BASE}/hiboss-1.0.0.zip`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${SECRET}`, 'content-type': 'application/zip' },
      body: 'zipbytes',
    });
    expect(put.status).toBe(201);

    const get = await SELF.fetch(`${BASE}/hiboss-1.0.0.zip`);
    expect(get.status).toBe(200);
    expect(get.headers.get('cache-control')).toContain('immutable');
    expect(await get.text()).toBe('zipbytes');
  });

  it('returns 500 when uploads are not configured', async () => {
    env.RELEASE_UPLOAD_SECRET = undefined;
    const res = await SELF.fetch(`${BASE}/hiboss-1.0.0.zip`, {
      method: 'PUT',
      headers: { Authorization: 'Bearer anything' },
      body: 'x',
    });
    expect(res.status).toBe(500);
  });
});
