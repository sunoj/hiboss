// Verifies the new Home discovery route retains existing boss authentication and scope.
// Covers invalid credentials, accessible agents, empty scope, and invalid cursors.
// Depends on the real Worker router, D1, and shared synthetic test identities.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import type { RequiredInputPage } from './boss-required-inputs';

const TOKEN = 'hb_boss_pending_scope_test_00000001';
const EMPTY_TOKEN = 'hb_boss_pending_empty_test_00000001';
const headers = { Authorization: `Bearer ${TOKEN}` };
const endpoint = 'http://localhost/api/boss/pending-inputs';

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('Pending Scope', 'manager', TOKEN);
  await seedBossToken('Pending Empty Scope', 'viewer', EMPTY_TOKEN);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(boss, getTestAgentId()).run();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('pending-hidden-agent', 'Hidden agent', 'synthetic-pending-hidden-key-hash').run();
  for (const [id, agent] of [['visible-ask', getTestAgentId()], ['hidden-ask', 'pending-hidden-agent']]) {
    await env.DB.prepare(
      `INSERT INTO messages (id, agent_id, direction, mode, body, status, priority)
       VALUES (?, ?, 'agent_to_boss', 'blocking', 'Which dataset?', 'sent', 'normal')`,
    ).bind(id, agent).run();
  }
});

it('requires boss authentication for pending discovery and its stream', async () => {
  expect((await SELF.fetch(endpoint)).status).toBe(401);
  expect((await SELF.fetch('http://localhost/api/boss/stream?inputs=true')).status).toBe(401);
});

it('returns required inputs only from agents in the existing boss scope', async () => {
  const response = await SELF.fetch(endpoint, { headers });
  expect(response.status).toBe(200);
  const page = await response.json() as RequiredInputPage;
  expect(page.messages.map(message => message.id)).toEqual(['visible-ask']);
  expect(page.next_cursor).toBeNull();
});

it('returns an explicit complete empty page for an empty scope', async () => {
  const response = await SELF.fetch(endpoint, { headers: { Authorization: `Bearer ${EMPTY_TOKEN}` } });
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ messages: [], next_cursor: null });
});

it('rejects a malformed cursor rather than silently restarting discovery', async () => {
  const response = await SELF.fetch(`${endpoint}?cursor=invalid`, { headers });
  expect(response.status).toBe(400);
});
