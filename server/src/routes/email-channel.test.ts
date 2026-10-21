// Email has no delivery adapter, so no write path may configure it as a channel.
// Covers channel config, agent and boss channel routing, routing rules, and send routing.
// Depends on the Worker (SELF), seeded D1, and test-helpers.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { resolveChannelRouting } from './message-options';

const BOSS = 'hb_email_channel_admin_0001';
const UNSUPPORTED = 'email is not a supported channel';
const boss = { Authorization: `Bearer ${BOSS}`, 'Content-Type': 'application/json' };

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Email Channel Admin', 'admin', BOSS, 'email-channel-admin');
  await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(getTestAgentId()).run();
});

async function expectRejected(res: Response): Promise<void> {
  expect(res.status).toBe(400);
  expect(await res.text()).toContain(UNSUPPORTED);
}

describe('email channel writes', () => {
  it('rejects an email channel config', async () => {
    await expectRejected(await SELF.fetch('https://test.local/api/channels/email', {
      method: 'PUT', headers: authHeaders(), body: JSON.stringify({ smtp_host: 'smtp.example.com' }),
    }));
    const row = await env.DB.prepare("SELECT id FROM channel_configs WHERE agent_id = ? AND channel = 'email'")
      .bind(getTestAgentId()).first();
    expect(row).toBeNull();
  });

  it('rejects email in agent and boss channel routing', async () => {
    await expectRejected(await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT', headers: authHeaders(), body: JSON.stringify({ channel_routing: { normal: 'email' } }),
    }));
    await expectRejected(await SELF.fetch(`https://test.local/api/boss/agents/${getTestAgentId()}/config`, {
      method: 'PATCH', headers: boss, body: JSON.stringify({ channel_routing: { normal: 'email' } }),
    }));
  });

  it('rejects email routing rules from agents and bosses', async () => {
    const rule = { channel: 'email', pattern: '.*', target_agent_id: getTestAgentId() };
    await expectRejected(await SELF.fetch('https://test.local/api/routing-rules', {
      method: 'POST', headers: authHeaders(), body: JSON.stringify(rule),
    }));
    await expectRejected(await SELF.fetch('https://test.local/api/boss/routing-rules', {
      method: 'POST', headers: boss, body: JSON.stringify({ ...rule, owner_agent_id: getTestAgentId() }),
    }));
  });

  it('ignores a stored email route when choosing the send channel', () => {
    expect(resolveChannelRouting(JSON.stringify({ normal: 'email' }), 'normal')).toBeUndefined();
    expect(resolveChannelRouting(JSON.stringify({ normal: 'telegram' }), 'normal')).toBe('telegram');
  });
});
