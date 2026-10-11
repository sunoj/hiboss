// Verifies registered avatars in the boss agent list without widening agent access.
// Dependencies: authenticated Worker requests, D1 fixtures, and public R2 attachments.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const avatarURL = 'http://localhost/api/attachments/agent-avatar.png';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Avatar Boss', 'viewer', 'avatar-boss', 'avatar-boss-token');
  await seedBossToken('Empty Boss', 'viewer', 'avatar-empty-boss', 'avatar-empty-token');
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind('avatar-boss', getTestAgentId()).run();
  await env.DB.prepare('UPDATE api_keys SET avatar_url = ? WHERE id = ?')
    .bind(avatarURL, getTestAgentId()).run();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash, avatar_url) VALUES (?, ?, ?, ?)')
    .bind('avatar-hidden', 'Hidden Agent', 'avatar-hidden-hash', avatarURL).run();
  await env.ATTACHMENTS.put('agent-avatar.png', new Uint8Array([137, 80, 78, 71]), {
    httpMetadata: { contentType: 'image/png' },
  });
});

async function agents(token = 'avatar-boss-token'): Promise<unknown> {
  const response = await SELF.fetch('http://localhost/api/boss/agents', {
    headers: { Authorization: `Bearer ${token}` },
  });
  expect(response.status).toBe(200);
  return response.json();
}

it('returns the registered avatar only for accessible agents', async () => {
  expect(await agents()).toMatchObject({ agents: [{ id: getTestAgentId(), avatar_url: avatarURL }] });
  const data = await agents() as { agents: { id: string }[] };
  expect(data.agents.map(agent => agent.id)).toEqual([getTestAgentId()]);
});

it('includes null when no avatar is registered', async () => {
  await env.DB.prepare('UPDATE api_keys SET avatar_url = NULL WHERE id = ?').bind(getTestAgentId()).run();
  expect(await agents()).toMatchObject({ agents: [{ id: getTestAgentId(), avatar_url: null }] });
});

it('keeps an empty accessible-agent list empty', async () => {
  expect(await agents('avatar-empty-token')).toEqual({ agents: [] });
});

it('serves attachment avatar bytes without boss authentication', async () => {
  const response = await SELF.fetch(avatarURL);
  expect(response.status).toBe(200);
  expect(response.headers.get('Content-Type')).toBe('image/png');
  expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([137, 80, 78, 71]));
});
