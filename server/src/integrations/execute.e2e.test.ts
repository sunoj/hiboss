// Posts real Discord webhook payload shapes to the compatible endpoint through the Worker and D1.
// Covers curl, Grafana (JSON and multipart), Uptime Kuma, auth that leaks nothing, limits and routing.
// Dependencies: cloudflare:test, vitest and the shared seed helpers.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import { redactWebhookPath } from './credentials';

interface Hook { agentId: string; sessionId: string; url: string; id: string }
interface Stored { body: string; priority: string; mode: string; direction: string; session_id: string;
  agent_id: string; metadata: string }

async function createHook(name: string): Promise<Hook> {
  const response = await SELF.fetch('https://test.local/api/integrations', { method: 'POST',
    headers: { ...authHeaders(), 'Content-Type': 'application/json' }, body: JSON.stringify({ name }) });
  const created = await response.json<{ agent_id: string; session_id: string; webhook: { id: string; url: string } }>();
  return { agentId: created.agent_id, sessionId: created.session_id, url: created.webhook.url, id: created.webhook.id };
}

function post(url: string, body: unknown): Promise<Response> {
  return SELF.fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}

async function latest(agentId: string): Promise<Stored & { meta: Record<string, unknown> }> {
  const row = await env.DB.prepare(`SELECT body, priority, mode, direction, session_id, agent_id, metadata
    FROM messages WHERE agent_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1`).bind(agentId).first<Stored>();
  expect(row).not.toBeNull();
  return { ...row!, meta: JSON.parse(row!.metadata) as Record<string, unknown> };
}

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(getTestAgentId()).run();
});

describe('Discord-compatible execute webhook', () => {
  it('stores a curl post in the integration session as an async notice', async () => {
    const hook = await createHook('Deploy script');
    const response = await post(hook.url, { content: 'Deploy finished: https://example.com/run/1' });
    expect(response.status).toBe(204);
    const stored = await latest(hook.agentId);
    expect(stored).toMatchObject({ body: 'Deploy finished: https://example.com/run/1', priority: 'normal',
      mode: 'async', direction: 'agent_to_boss', session_id: hook.sessionId });
    expect(stored.meta).toMatchObject({ source: 'webhook', provenance: { authentication: { kind: 'webhook_token',
      credential_id: hook.id } } });
    expect(stored.meta.options).toBeUndefined();
    const session = await env.DB.prepare('SELECT status, status_text FROM sessions WHERE id = ?')
      .bind(hook.sessionId).first();
    expect(session).toEqual({ status: 'idle', status_text: 'Deploy finished: https://example.com/run/1' });
  });

  it('renders Grafana and Uptime Kuma embeds, and ?wait=true returns the message object', async () => {
    const hook = await createHook('Grafana');
    const grafana = await post(`${hook.url}?wait=true`, { username: 'Grafana', content: '', embeds: [{
      title: '[FIRING:1] HighCPU', url: 'https://grafana.example/alerting/list',
      description: '**Value**: 97%', color: 14037554, footer: { text: 'Grafana v11', icon_url: 'https://x/i.png' } }] });
    expect(grafana.status).toBe(200);
    expect(await grafana.json()).toMatchObject({ type: 0, webhook_id: hook.id, author: { bot: true } });
    const stored = await latest(hook.agentId);
    expect(stored.body).toBe('[FIRING:1] HighCPU');
    expect(stored.meta.content).toContain('**[FIRING:1 HighCPU](https://grafana.example/alerting/list)**');
    expect(stored.meta.content).toContain('*Grafana v11*');
    const kuma = await post(hook.url, { username: 'Uptime Kuma', embeds: [{ title: '❌ Site down',
      fields: [{ name: 'Time', value: '<t:1795500000:F>' }, { name: 'Ping', value: '<@123> <#456>' }] }],
      components: [{ type: 1 }], poll: { question: { text: 'never' } } });
    expect(kuma.status).toBe(204);
    const down = await latest(hook.agentId);
    expect(down.meta.content).toContain('- **Time**: 2026-11-24 0');
    expect(down.meta.content).toContain('@user #channel');
    expect(down.meta.content).toContain('*via Uptime Kuma*');
    expect(down.mode).toBe('async');
  });

  it('answers every bad credential the same way and rejects empty or malformed bodies', async () => {
    const hook = await createHook('Credential checks');
    const [, , , , id, token] = new URL(hook.url).pathname.split('/');
    const wrongToken = await post(`https://test.local/api/webhooks/${id}/${'x'.repeat(64)}`, { content: 'x' });
    const unknownId = await post(`https://test.local/api/webhooks/1234567890123456789/${token}`, { content: 'x' });
    expect(wrongToken.status).toBe(404);
    expect(await wrongToken.json()).toEqual(await unknownId.json());
    expect((await post(hook.url, { content: '  ' })).status).toBe(400);
    const malformed = await SELF.fetch(hook.url, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: '{"content":' });
    expect(await malformed.json()).toEqual({ message: 'Invalid Form Body', code: 50035 });
    const info = await SELF.fetch(`https://test.local/api/v10/webhooks/${id}/${token}`);
    expect(await info.json()).toMatchObject({ id, type: 1, name: 'Credential checks' });
  });

  it('lowers SUPPRESS_NOTIFICATIONS posts, rate limits per integration and caps the body', async () => {
    const hook = await createHook('Noisy CI');
    await post(hook.url, { content: 'quiet', flags: 4096 });
    expect((await latest(hook.agentId)).priority).toBe('low');
    await env.DB.prepare('UPDATE api_keys SET rate_limit = 1 WHERE id = ?').bind(hook.agentId).run();
    const limited = await post(hook.url, { content: 'second' });
    expect(limited.status).toBe(429);
    expect(limited.headers.get('Retry-After')).toBe('60');
    expect(await limited.json()).toMatchObject({ retry_after: 60, global: false });
    const huge = await post(hook.url, { content: 'x'.repeat(300 * 1024) });
    expect(huge.status).toBe(413);
    expect(await huge.json()).toEqual({ message: 'Request entity too large', code: 40005 });
  });

  it('stores an image part with an empty field name and lists other files', async () => {
    const hook = await createHook('Grafana images');
    const form = new FormData();
    form.append('payload_json', JSON.stringify({ embeds: [{ title: 'Panel snapshot', image: { url: 'attachment://p.png' } }] }));
    form.append('', new File([PNG], 'p.png', { type: 'image/png' }));
    form.append('files[1]', new File(['hello'], 'notes.txt', { type: 'text/plain' }));
    expect((await SELF.fetch(hook.url, { method: 'POST', body: form })).status).toBe(204);
    const stored = await latest(hook.agentId);
    expect(stored.meta.file_url).toMatch(/^https:\/\/test\.local\/api\/attachments\/[0-9a-f-]+\.png$/);
    expect(stored.meta.content).toContain('file not stored: notes.txt');
  });

  it('keeps named webhook routes, never logs a token, and hides integrations from --to', async () => {
    const telegram = await SELF.fetch('https://test.local/api/webhooks/telegram', { method: 'POST', body: '{}' });
    expect(await telegram.text()).not.toContain('Unknown Webhook');
    expect(redactWebhookPath('/api/webhooks/1234567890123456789/secret-token')).toBe('/api/webhooks/1234567890123456789/***');
    const hook = await createHook('Hidden target');
    const send = await SELF.fetch('https://test.local/api/messages', { method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'hello', to: 'Hidden target' }) });
    expect(send.status).toBe(404);
    const toAgent = await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE target_agent_id = ?')
      .bind(hook.agentId).first<{ n: number }>();
    expect(toAgent?.n).toBe(0);
  });
});
