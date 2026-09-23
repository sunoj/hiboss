// Security regressions for foreign-session streams, active attachments, and bootstrap.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, seedDatabase } from '../test-helpers';
import { createAgent } from '../agent-keys';
import { buildStreamQuery } from './stream';

beforeAll(seedDatabase);
const base = 'https://test.local';

describe('Security review 2026-09-23 regressions', () => {
  it('rejects foreign sessions and preserves the intended recipient delivery', async () => {
    const victim = await createAgent(env.DB, 'review-victim', { type: 'system', id: 'review' });
    const sender = await createAgent(env.DB, 'review-sender', { type: 'system', id: 'review' });
    if (!victim || !sender) throw new Error('fixture creation failed');
    const session = 'review-victim-session';
    const message = 'review-private-message';
    await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, victim.id).run();
    await env.DB.prepare(`INSERT INTO messages
      (id, agent_id, direction, mode, body, status, target_agent_id, target_session_id, created_at)
      VALUES (?, ?, 'agent_to_agent', 'async', 'private review payload', 'sent', ?, ?, datetime('now', '+1 minute'))`)
      .bind(message, sender.id, victim.id, session).run();
    try {
      const response = await SELF.fetch(`${base}/api/messages/stream?session=${session}`, { headers: authHeaders() });
      expect(response.status).toBe(404);
      expect(await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(message).first())
        .toEqual({ status: 'sent' });
      // The query must remain isolated even if a caller bypasses session preflight.
      const query = buildStreamQuery('test-agent-id', session);
      expect((await env.DB.prepare(query.sql).bind(...query.buildBinds('2000-01-01')).all()).results).toEqual([]);
      const authorized = await SELF.fetch(`${base}/api/messages/stream?session=${session}`, {
        headers: { Authorization: `Bearer ${victim.key}` },
      });
      expect(authorized.status).toBe(200);
      const reader = authorized.body!.getReader();
      try {
        const chunk = await reader.read();
        expect(new TextDecoder().decode(chunk.value)).toContain('private review payload');
      } finally {
        await reader.cancel();
      }
      expect(await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(message).first())
        .toEqual({ status: 'delivered' });
    } finally {
      await env.DB.prepare('DELETE FROM messages WHERE id = ?').bind(message).run();
      await env.DB.prepare('DELETE FROM sessions WHERE id = ?').bind(session).run();
      await env.DB.prepare('DELETE FROM api_keys WHERE id IN (?, ?)').bind(victim.id, sender.id).run();
    }
  });

  it.each([
    ['text/html', 'review.html', '<script>document.title = localStorage.getItem("hiboss_key") || "no-key"</script>'],
    ['image/svg+xml', 'review.svg', '<svg xmlns="http://www.w3.org/2000/svg" onload="document.title = localStorage.getItem(\'hiboss_key\') || \'no-key\'"></svg>'],
  ])('forces safe downloads for active %s attachments on GET, HEAD, and ranges', async (mime, filename, payload) => {
    const headers = authHeaders();
    delete headers['Content-Type'];
    const body = new FormData();
    body.set('file', new File([payload], filename, { type: mime }));
    const upload = await SELF.fetch(`${base}/api/attachments/upload`, { method: 'POST', headers, body });
    expect(upload.status).toBe(201);
    const { url } = await upload.json() as { url: string };
    expect(new URL(url).origin).toBe(base);
    for (const init of [{}, { method: 'HEAD' }, { headers: { Range: 'bytes=0-9' } }]) {
      const download = await SELF.fetch(url, init);
      expect(download.status).toBe('headers' in init ? 206 : 200);
      expect(download.headers.get('content-type')).toBe('application/octet-stream');
      expect(download.headers.get('content-disposition')).toMatch(/^attachment;/);
      expect(download.headers.get('content-security-policy')).toContain('sandbox');
      expect(download.headers.get('x-content-type-options')).toBe('nosniff');
      expect(download.headers.get('cache-control')).toBe('no-store');
      expect(await download.text()).toBe(init.method === 'HEAD' ? '' : 'headers' in init ? payload.slice(0, 10) : payload);
    }
  });

  it.each(['Authorization', 'X-Bootstrap-Secret'])('requires the configured bootstrap secret and accepts %s for first join', async (secretHeader) => {
    const previousSecret = env.BOOTSTRAP_SECRET;
    await env.DB.prepare('DELETE FROM api_keys').run();
    await env.DB.prepare(`CREATE TABLE IF NOT EXISTS join_requests (
      id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL,
      poll_token TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'pending',
      api_key_id TEXT REFERENCES api_keys(id), api_key TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`).run();
    env.BOOTSTRAP_SECRET = 'review-bootstrap-secret';
    try {
      const bootstrap = await SELF.fetch(`${base}/api/bootstrap`, { method: 'POST' });
      expect(bootstrap.status).toBe(401);
      const invalidHeaders: Record<string, string>[] = [{}, { Authorization: 'Bearer wrong' }, { 'X-Bootstrap-Secret': 'wrong' }];
      for (const headers of invalidHeaders) {
        const denied = await SELF.fetch(`${base}/api/join`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', ...headers },
          body: JSON.stringify({ name: 'review-unauthorized-agent' }),
        });
        expect(denied.status).toBe(401);
      }
      expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM api_keys').first()).toEqual({ count: 0 });
      expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM join_requests').first()).toEqual({ count: 0 });
      const join = await SELF.fetch(`${base}/api/join`, {
        method: 'POST',
        body: JSON.stringify({ name: 'review-authorized-agent' }),
        headers: { 'Content-Type': 'application/json', [secretHeader]: secretHeader === 'Authorization'
          ? 'Bearer review-bootstrap-secret' : 'review-bootstrap-secret' },
      });
      expect(join.status).toBe(201);
      const grant = await join.json() as { status: string; key: string; agent_id: string };
      expect(grant.status).toBe('approved');
      const profile = await SELF.fetch(`${base}/api/agents/me`, {
        headers: { Authorization: `Bearer ${grant.key}` },
      });
      expect(profile.status).toBe(200);
      expect(await profile.json()).toMatchObject({ id: grant.agent_id });
      const pending = await SELF.fetch(`${base}/api/join`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'review-pending-agent' }),
      });
      expect(pending.status).toBe(201);
      expect(await pending.json()).toMatchObject({ status: 'pending' });
    } finally {
      env.BOOTSTRAP_SECRET = previousSecret;
      await env.DB.prepare('DELETE FROM join_requests').run();
      await env.DB.prepare('DELETE FROM api_keys').run();
    }
  });
});
