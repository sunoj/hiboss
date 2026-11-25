// Exercises integration creation and webhook URL management against the real Worker and D1.
// Verifies tokens are shown once and stored hashed, and that integrations can never hold keys.
// Dependencies: cloudflare:test, vitest, the shared seed helpers and the credential lookup.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import { prepareKey } from '../agent-keys/repository';
import { findWebhook } from './credentials';

const base = 'https://test.local/api/integrations';
interface Created { agent_id: string; session_id: string; webhook: { id: string; url: string } }

function call(path: string, method = 'POST', body?: unknown, headers = authHeaders()): Promise<Response> {
  return SELF.fetch(base + path, { method, headers: { ...headers, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body) });
}

function tokenOf(url: string): { id: string; token: string } {
  const [, id, token] = new URL(url).pathname.match(/^\/api\/webhooks\/(\d+)\/([A-Za-z0-9_-]+)$/) ?? [];
  return { id, token };
}

async function create(name: string): Promise<Created> {
  const response = await call('', 'POST', { name });
  expect(response.status).toBe(201);
  return response.json<Created>();
}

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(getTestAgentId()).run();
});

describe('integration management', () => {
  it('creates a key-less integration with its own project, idle session and a once-shown URL', async () => {
    const created = await create('Grafana prod');
    const { id, token } = tokenOf(created.webhook.url);
    expect(id).toMatch(/^[1-9]\d{18}$/);
    expect(token).toHaveLength(64);
    const agent = await env.DB.prepare('SELECT kind, key_hash FROM api_keys WHERE id = ?')
      .bind(created.agent_id).first();
    expect(agent).toEqual({ kind: 'integration', key_hash: null });
    // No project: the apps title a project-less session with its label, the integration's name.
    const session = await env.DB.prepare(`SELECT status, runtime, label, project_id FROM sessions
      WHERE id = ? AND agent_id = ?`).bind(created.session_id, created.agent_id).first<Record<string, string>>();
    expect(session).toEqual({ status: 'idle', runtime: 'webhook', label: 'Grafana prod', project_id: null });
    expect((await findWebhook(env.DB, id, token))?.agent_id).toBe(created.agent_id);
    const stored = await env.DB.prepare('SELECT token_hash FROM agent_webhooks WHERE id = ?').bind(id)
      .first<{ token_hash: string }>();
    expect(stored?.token_hash).not.toContain(token);
    const listed = await (await call('', 'GET')).text();
    expect(listed).toContain(id);
    expect(listed).not.toContain(token);
  });

  it('refuses duplicates, bad caps and non-admin callers', async () => {
    await create('Uptime Kuma');
    expect((await call('', 'POST', { name: 'Uptime Kuma' })).status).toBe(409);
    expect((await call('', 'POST', { name: 'Other', priority_cap: 'critical' })).status).toBe(400);
    await env.DB.prepare('UPDATE api_keys SET is_admin = 0 WHERE id = ?').bind(getTestAgentId()).run();
    try {
      expect((await call('', 'POST', { name: 'Not allowed' })).status).toBe(403);
    } finally {
      await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(getTestAgentId()).run();
    }
  });

  it('never mints an agent key for an integration', async () => {
    const created = await create('CI pipeline');
    const key = await prepareKey(env.DB, created.agent_id, 'should-fail');
    const result = await key.statement.all();
    expect(result.results).toHaveLength(0);
    const keys = await env.DB.prepare('SELECT COUNT(*) AS n FROM agent_keys WHERE agent_id = ?')
      .bind(created.agent_id).first<{ n: number }>();
    expect(keys?.n).toBe(0);
  });

  it('rotates a URL in place, adds another one, and revokes', async () => {
    const created = await create('Watch scripts');
    const first = tokenOf(created.webhook.url);
    const rotated = await call(`/webhooks/${first.id}/rotate`);
    expect(rotated.status).toBe(200);
    const next = tokenOf((await rotated.json<{ url: string }>()).url);
    expect(next.id).toBe(first.id);
    expect(await findWebhook(env.DB, first.id, first.token)).toBeNull();
    expect(await findWebhook(env.DB, next.id, next.token)).not.toBeNull();
    const added = await call(`/${created.agent_id}/webhooks`, 'POST', { label: 'staging' });
    expect(added.status).toBe(201);
    const second = tokenOf((await added.json<{ url: string }>()).url);
    expect((await findWebhook(env.DB, second.id, second.token))?.session_id).toBe(created.session_id);
    expect((await call(`/webhooks/${next.id}`, 'DELETE')).status).toBe(204);
    expect(await findWebhook(env.DB, next.id, next.token)).toBeNull();
    expect((await call(`/webhooks/${next.id}`, 'DELETE')).status).toBe(404);
    expect((await call(`/${getTestAgentId()}/webhooks`, 'POST', { label: 'not an integration' })).status).toBe(404);
  });
});
