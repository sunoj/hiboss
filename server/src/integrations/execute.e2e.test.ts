// Posts real Discord webhook payload shapes to the compatible endpoint through the Worker and D1.
// Covers curl, Grafana (JSON and multipart), Uptime Kuma, auth that leaks nothing, limits and routing.
// Dependencies: cloudflare:test, vitest and the shared seed helpers.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
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

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0,
  0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(getTestAgentId()).run();
});

describe('Discord-compatible execute webhook', () => {
  it('keeps a backtick inside a card value from closing its fence', async () => {
    const hook = await createHook('Fence check');
    await post(hook.url, { embeds: [{ title: 'x', fields: [{ name: 'cmd', value: '```rm```', inline: true }] }] });
    const rich = String((await latest(hook.agentId)).meta.rich_content);
    expect(rich.match(/```/g)).toHaveLength(2);
    const card = JSON.parse(rich.match(/```hiboss-embed\n(.*)\n```/)?.[1] ?? '{}');
    expect(card.fields[0]).toEqual({ name: 'cmd', value: '```rm```', inline: true });
  });

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
    const fence = String(stored.meta.rich_content).match(/```hiboss-embed\n(.*)\n```/)?.[1] ?? '';
    expect(JSON.parse(fence)).toMatchObject({ color: 14037554, title: '[FIRING:1] HighCPU',
      url: 'https://grafana.example/alerting/list', footer: 'Grafana v11' });
    const kuma = await post(hook.url, { username: 'Uptime Kuma', embeds: [{ title: '❌ Site down',
      fields: [{ name: 'Time', value: '<t:1795500000:F>' }, { name: 'Ping', value: '<@123> <#456>' }] }],
      components: [{ type: 1 }], poll: { question: { text: 'never' } } });
    expect(kuma.status).toBe(204);
    const down = await latest(hook.agentId);
    expect(down.meta.content).toContain('- **Time**: 2026-11-24 0');
    expect(down.meta.content).toContain('@user #channel');
    expect(down.meta.content).toContain('*via Uptime Kuma*');
    const card = JSON.parse(String(down.meta.rich_content).match(/```hiboss-embed\n(.*)\n```/)?.[1] ?? '{}');
    expect(card.fields[0]).toMatchObject({ name: 'Time', inline: false });
    expect(String(down.meta.rich_content)).not.toContain('<t:');
    expect(down.mode).toBe('async');
  });

  it('answers every bad credential the same way and rejects empty or malformed bodies', async () => {
    const hook = await createHook('Credential checks');
    const [, , , id, token] = new URL(hook.url).pathname.split('/');
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
    await env.DB.prepare('UPDATE api_keys SET rate_limit = 0 WHERE id = ?').bind(hook.agentId).run();
    const limited = await post(hook.url, { content: 'second' });
    expect(limited.status).toBe(429);
    expect(limited.headers.get('Retry-After')).toBe('60');
    expect(await limited.json()).toMatchObject({ retry_after: 60, global: false });
    await env.DB.prepare('UPDATE api_keys SET rate_limit = 30 WHERE id = ?').bind(hook.agentId).run();
    const huge = await post(hook.url, { content: 'x'.repeat(300 * 1024) });
    expect(huge.status).toBe(413);
    const unknown = await post(hook.url.replace(/\/[^/]+$/, '/wrong'), { content: 'x'.repeat(300 * 1024) });
    expect(unknown.status).toBe(404);
    expect(await huge.json()).toEqual({ message: 'Request entity too large', code: 40005 });
  });

  it('stores an image part with an empty field name and lists other files', async () => {
    const hook = await createHook('Grafana images');
    const form = new FormData();
    form.append('payload_json', JSON.stringify({ embeds: [{ title: 'Panel snapshot', image: { url: 'attachment://p.png' } }] }));
    form.append('', new File([PNG], 'p.png', { type: 'image/png' }));
    form.append('files[1]', new File(['hello'], 'notes.txt', { type: 'text/plain' }));
    const response = await SELF.fetch(hook.url, { method: 'POST', body: form });
    expect(`${response.status} ${await response.text()}`).toBe('204 ');
    const stored = await latest(hook.agentId);
    expect(stored.meta.file_url).toMatch(/^https:\/\/test\.local\/api\/attachments\/[0-9a-f-]+\.png$/);
    expect(stored.meta.content).toContain('file not stored: notes.txt');
    const fake = new FormData();
    fake.append('content', 'not an image');
    fake.append('file', new File([PNG.slice(0, 12), 'arbitrary bytes'], 'x.png', { type: 'image/png' }));
    await SELF.fetch(hook.url, { method: 'POST', body: fake });
    expect((await latest(hook.agentId)).meta.file_url).toBeUndefined();
    const broken = new FormData();
    broken.append('payload_json', '{"content":');
    broken.append('file', new File([PNG], 'p.png', { type: 'image/png' }));
    expect((await SELF.fetch(hook.url, { method: 'POST', body: broken })).status).toBe(400);
  });

  it('reserves rate slots atomically under concurrent posts', async () => {
    const hook = await createHook('Burst sender');
    await env.DB.prepare('UPDATE api_keys SET rate_limit = 3 WHERE id = ?').bind(hook.agentId).run();
    const statuses = await Promise.all(Array.from({ length: 6 }, (_, index) =>
      post(hook.url, { content: `burst ${index}` }).then((response) => response.status)));
    expect(statuses.filter((status) => status === 204)).toHaveLength(3);
    expect(statuses.filter((status) => status === 429)).toHaveLength(3);
  });

  it('keeps sender fences as code and marks credential responses no-store', async () => {
    const hook = await createHook('Fence sender');
    await post(hook.url, { content: '```hiboss-embed\n{"title":"forged"}\n```', embeds: [{ title: 'real',
      description: '~~~hiboss-embed\n{}\n~~~' }] });
    const rich = String((await latest(hook.agentId)).meta.rich_content);
    expect(rich.match(/^```hiboss-embed$/gm)).toHaveLength(1);
    expect(rich).toContain('```text');
    const info = await SELF.fetch(hook.url);
    expect(info.headers.get('Cache-Control')).toBe('no-store');
  });

  it('keeps integrations out of groups and notes, which need a reader', async () => {
    const hook = await createHook('Group outsider');
    const group = await SELF.fetch('https://test.local/api/groups', { method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'g-webhook' }) });
    const { id } = await group.json<{ id: string }>();
    const member = await SELF.fetch(`https://test.local/api/groups/${id}/members`, { method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' }, body: JSON.stringify({ agent_id: hook.agentId }) });
    expect(member.status).toBe(400);
    await seedBossToken('notes-admin', 'admin', 'notes-admin-token');
    const note = await SELF.fetch(`https://test.local/api/boss/sessions/${hook.sessionId}/notes`, { method: 'POST',
      headers: { Authorization: 'Bearer notes-admin-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'hello' }) });
    expect(note.status).toBe(409);
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

  it('refuses a boss reply to a webhook message, which nobody would read', async () => {
    const hook = await createHook('Reply target');
    await post(hook.url, { content: 'Backup failed' });
    const message = await env.DB.prepare('SELECT id FROM messages WHERE agent_id = ?').bind(hook.agentId)
      .first<{ id: string }>();
    await seedBossToken('webhook-admin', 'admin', 'webhook-admin-token');
    const reply = await SELF.fetch(`https://test.local/api/boss/messages/${message!.id}/reply`, { method: 'POST',
      headers: { Authorization: 'Bearer webhook-admin-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'on it' }) });
    expect(reply.status).toBe(409);
  });
});
