// Channel toggle integration tests through the authenticated Worker API.
// Covers scope, validation, projection, persistence, warnings, and auditing.
// Depends on cloudflare:test, Vitest, and shared database fixtures.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { seedDatabase } from '../test-helpers';

const AGENT = 'channel-toggle-agent';
const OTHER = 'channel-toggle-other';
const WARNING = 'agent has no enabled channel; hiboss send will fail';

beforeAll(async () => {
  await seedDatabase();
  for (const id of [AGENT, OTHER]) {
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(id, id, await hashApiKey(id)).run();
  }
  for (const role of ['admin', 'manager', 'viewer']) {
    const id = `channel-toggle-${role}`;
    await env.DB.prepare('INSERT INTO bosses (id, name, role) VALUES (?, ?, ?)').bind(id, id, role).run();
    await env.DB.prepare('INSERT INTO boss_tokens (boss_id, label, token_hash) VALUES (?, ?, ?)')
      .bind(id, 'test', await hashApiKey(id)).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(id, AGENT).run();
  }
});

beforeEach(async () => {
  for (const [id, agent, channel] of [['toggle-email', AGENT, 'email'], ['toggle-api', AGENT, 'api'], ['toggle-other', OTHER, 'email']]) {
    await env.DB.prepare('INSERT INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, ?, ?, 1) ON CONFLICT(id) DO UPDATE SET enabled = 1')
      .bind(id, agent, channel, JSON.stringify({ label: 'Ops', bot_token: 'secret', webhook_url: 'secret', enabled: 99 })).run();
  }
});

function headers(role = 'manager'): Record<string, string> {
  return { Authorization: `Bearer channel-toggle-${role}`, 'Content-Type': 'application/json' };
}

function patch(id: string, body: unknown, role = 'manager'): Promise<Response> {
  return SELF.fetch(`https://test.local/api/boss/channels/${id}`, {
    method: 'PATCH', headers: headers(role), body: JSON.stringify(body),
  });
}

describe('boss channel toggle', () => {
  it('disables and re-enables an accessible channel with the GET projection', async () => {
    for (const enabled of [false, true]) {
      const response = await patch('toggle-email', { enabled });
      expect(response.status).toBe(200);
      const row = await response.json();
      expect(row).toMatchObject({ id: 'toggle-email', agent_id: AGENT, agent_name: AGENT, channel: 'email', enabled: Number(enabled), configured: enabled, label: 'Ops' });
      expect(row).not.toHaveProperty('warning');
      expect(row).not.toHaveProperty('bot_token');
      expect(row).not.toHaveProperty('webhook_url');
      const list = await SELF.fetch('https://test.local/api/boss/channels', { headers: headers() });
      expect(await list.json()).toContainEqual(row);
    }
  });

  it('allows disabling the last channel and warns despite another agent having a channel', async () => {
    await patch('toggle-api', { enabled: false });
    const response = await patch('toggle-email', { enabled: false });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ enabled: 0, warning: WARNING });
    const stored = await env.DB.prepare('SELECT enabled FROM channel_configs WHERE id = ?').bind('toggle-email').first();
    expect(stored).toEqual({ enabled: 0 });
    const enabled = await patch('toggle-api', { enabled: true });
    expect(await enabled.json()).not.toHaveProperty('warning');
  });

  it('allows admins to update agents without an explicit grant and audits the change', async () => {
    const response = await patch('toggle-other', { enabled: false }, 'admin');
    expect(response.status).toBe(200);
    await expect.poll(async () => env.DB.prepare("SELECT actor_type, actor_id, resource_type, details FROM audit_log WHERE action = 'channel.update' AND resource_id = 'toggle-other'").first()).toEqual({
      actor_type: 'boss', actor_id: 'channel-toggle-admin', resource_type: 'channel_config', details: '{"enabled":false}',
    });
  });

});

describe('boss channel toggle authorization and validation', () => {
  it('requires boss authentication and denies viewer writes', async () => {
    const anonymous = await SELF.fetch('https://test.local/api/boss/channels/toggle-email', { method: 'PATCH', body: '{"enabled":false}' });
    expect(anonymous.status).toBe(401);
    expect((await patch('toggle-email', { enabled: false }, 'viewer')).status).toBe(403);
    expect(await env.DB.prepare("SELECT enabled FROM channel_configs WHERE id = 'toggle-email'").first()).toEqual({ enabled: 1 });
  });

  it.each(['toggle-other', 'missing'])('returns 404 for inaccessible or missing row %s', async (id) => {
    expect((await patch(id, { enabled: false })).status).toBe(404);
    expect(await env.DB.prepare("SELECT enabled FROM channel_configs WHERE id = 'toggle-other'").first()).toEqual({ enabled: 1 });
  });

  it.each([{}, null, [], { enabled: 1 }, { enabled: 'false' }, { enabled: null }])('rejects non-boolean input %j', async (body) => {
    expect((await patch('toggle-email', body)).status).toBe(400);
    expect(await env.DB.prepare("SELECT enabled FROM channel_configs WHERE id = 'toggle-email'").first()).toEqual({ enabled: 1 });
  });

  it('rejects malformed JSON', async () => {
    const response = await SELF.fetch('https://test.local/api/boss/channels/toggle-email', { method: 'PATCH', headers: headers(), body: '{' });
    expect(response.status).toBe(400);
  });
});
