// Guards the public attachment boundary for private Box objects.
// Uses real R2 objects and HTTP requests, including encoded object keys.
import { env, SELF } from 'cloudflare:test';
import { expect, it } from 'vitest';

it('refuses existing Box objects through public GET and HEAD attachment routes', async () => {
  const key = 'box/private-boss/reference.png';
  await env.ATTACHMENTS.put(key, 'private image', { httpMetadata: { contentType: 'image/png' } });
  for (const path of [key, encodeURIComponent(key), 'box%2fprivate-boss%2freference.png',
    '%62ox%2Fprivate-boss%2Freference.png']) {
    for (const method of ['GET', 'HEAD']) {
      const response = await SELF.fetch(`https://test.local/api/attachments/${path}`, { method });
      expect(response.status, `${method} ${path}`).toBe(404);
      if (method === 'GET') expect(await response.text()).not.toContain('private image');
    }
  }
});
