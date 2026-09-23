// Exercises media upload and byte-range downloads through the running Worker.
// Covers playback probes, seeking, validators, HEAD, and invalid ranges against R2.
// Dependencies: cloudflare:test SELF, Vitest, and isolated test authentication.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, seedDatabase } from '../test-helpers';

const CONTENT = '0123456789';
let mediaUrl: string;

beforeAll(async () => {
  await seedDatabase();
  const response = await SELF.fetch('https://test.local/api/attachments/upload', {
    method: 'POST',
    headers: { ...authHeaders(), 'Content-Type': 'video/mp4', 'X-Filename': 'clip.mp4' },
    body: CONTENT,
  });
  expect(response.status).toBe(201);
  const uploaded = await response.json() as { url: string };
  mediaUrl = uploaded.url;
});

describe('media byte-range delivery', () => {
  it('hardens legacy documents and safely encodes stored filenames', async () => {
    await env.ATTACHMENTS.put('legacy-active-document', '<script>alert(1)</script>', {
      httpMetadata: { contentType: 'text/html' },
      customMetadata: { filename: 'report"\\\r\n☃.html' },
    });
    const response = await SELF.fetch('https://test.local/api/attachments/legacy-active-document');
    expect(response.headers.get('content-type')).toBe('application/octet-stream');
    const disposition = response.headers.get('content-disposition')!;
    expect(disposition).toMatch(/^attachment; filename="report_____\.html";/);
    expect(disposition).toContain("filename*=UTF-8''report%22%5C__%E2%98%83.html");
    expect(response.headers.get('content-security-policy')).toContain('sandbox');
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(await response.text()).toBe('<script>alert(1)</script>');
  });

  it('advertises size and range support for a complete download', async () => {
    const response = await SELF.fetch(mediaUrl);
    expect(response.status).toBe(200);
    expect(response.headers.get('accept-ranges')).toBe('bytes');
    expect(response.headers.get('content-length')).toBe('10');
    expect(response.headers.get('content-type')).toBe('video/mp4');
    expect(response.headers.get('content-disposition')).toMatch(/^inline;/);
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
    expect(response.headers.get('etag')).toMatch(/^".+"$/);
    expect(response.headers.get('content-range')).toBeNull();
    expect(await response.text()).toBe(CONTENT);
  });

  it.each([
    ['bytes=0-1', '01', 'bytes 0-1/10'],
    ['bytes=4-6', '456', 'bytes 4-6/10'],
    ['bytes=7-', '789', 'bytes 7-9/10'],
    ['bytes=-3', '789', 'bytes 7-9/10'],
    ['bytes=8-999', '89', 'bytes 8-9/10'],
    ['bytes=-999', CONTENT, 'bytes 0-9/10'],
    ['bytes=0-999999999999999999999999', CONTENT, 'bytes 0-9/10'],
  ])('serves %s without downloading unrelated bytes', async (range, body, contentRange) => {
    const response = await SELF.fetch(mediaUrl, { headers: { Range: range } });
    expect(response.status).toBe(206);
    expect(response.headers.get('content-range')).toBe(contentRange);
    expect(response.headers.get('content-length')).toBe(String(body.length));
    expect(response.headers.get('content-type')).toBe('video/mp4');
    expect(await response.text()).toBe(body);
  });

  it.each(['bytes=10-', 'bytes=20-30', 'bytes=-0', 'bytes=999999999999999999999999-']) (
    'rejects unsatisfiable %s with the current size', async (range) => {
      const response = await SELF.fetch(mediaUrl, { headers: { Range: range } });
      expect(response.status).toBe(416);
      expect(response.headers.get('content-range')).toBe('bytes */10');
      expect(await response.text()).toBe('');
    },
  );

  it.each(['bytes=6-2', 'bytes=abc', 'bytes=-', 'items=0-1', 'bytes=0-1,4-5']) (
    'ignores unsupported or malformed %s', async (range) => {
      const response = await SELF.fetch(mediaUrl, { headers: { Range: range } });
      expect(response.status).toBe(200);
      expect(response.headers.get('content-range')).toBeNull();
      expect(await response.text()).toBe(CONTENT);
    },
  );

  it('answers HEAD with full metadata and no body even when Range is supplied', async () => {
    const response = await SELF.fetch(mediaUrl, { method: 'HEAD', headers: { Range: 'bytes=0-1' } });
    expect(response.status).toBe(200);
    expect(response.headers.get('content-length')).toBe('10');
    expect(response.headers.get('accept-ranges')).toBe('bytes');
    expect(response.headers.get('content-range')).toBeNull();
    expect(await response.text()).toBe('');
  });

  it('honors If-Range only for the current strong ETag', async () => {
    const head = await SELF.fetch(mediaUrl, { method: 'HEAD' });
    const etag = head.headers.get('etag');
    expect(etag).toBeTruthy();
    const response = await SELF.fetch(mediaUrl, {
      headers: { Range: 'bytes=2-3', 'If-Range': etag! },
    });
    expect(response.status).toBe(206);
    expect(await response.text()).toBe('23');
    for (const validator of ['"old"', `W/${etag}`, 'Wed, 01 Jan 2020 00:00:00 GMT']) {
      const full = await SELF.fetch(mediaUrl, {
        headers: { Range: 'bytes=2-3', 'If-Range': validator },
      });
      expect(full.status).toBe(200);
      expect(await full.text()).toBe(CONTENT);
    }
  });

  it('keeps missing media a 404 for GET and HEAD', async () => {
    for (const method of ['GET', 'HEAD']) {
      const response = await SELF.fetch('https://test.local/api/attachments/missing.mp4', {
        method, headers: { Range: 'bytes=0-1' },
      });
      expect(response.status).toBe(404);
      await response.arrayBuffer();
    }
  });
});
