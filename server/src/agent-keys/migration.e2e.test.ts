// Real D1 migration transaction over seven existing identities and referenced messages.
// Exercises 0045 and unchanged bearer auth; depends on the pre-phase-4 seed and Worker.
import { env, SELF } from 'cloudflare:test';
import { expect, it } from 'vitest';
import { seedPreAgentKeysDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import migration from '../../migrations/0045_agent_keys.sql?raw';

it('backfills seven agents atomically in D1 without rebuilding messages or changing their bearers', async () => {
  await seedPreAgentKeysDatabase();
  for (let i = 0; i < 7; i++) {
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash, role) VALUES (?, ?, ?, ?)')
      .bind(`agent-${i}`, `agent-${i}`, await hashApiKey(`old-bearer-${i}`), i === 0 ? 'admin' : 'worker').run();
    await env.DB.prepare("INSERT INTO messages (agent_id, direction, mode, body) VALUES (?, 'agent_to_boss', 'async', 'existing')")
      .bind(`agent-${i}`).run();
  }
  const tableBefore = await env.DB.prepare("SELECT sql, rootpage FROM sqlite_master WHERE name = 'messages'").first();
  const before = await env.DB.prepare('SELECT * FROM messages ORDER BY id').all();
  const adminHeaders = { Authorization: 'Bearer old-bearer-0' };
  expect((await SELF.fetch('https://test.local/__test/legacy-admin', { headers: adminHeaders })).status).toBe(200);
  const statements = migration.replace(/^--.*$/gm, '').split(';').map(s => s.trim()).filter(Boolean);
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
  expect(await env.DB.prepare("SELECT sql, rootpage FROM sqlite_master WHERE name = 'messages'").first()).toEqual(tableBefore);
  expect((await env.DB.prepare('SELECT * FROM messages ORDER BY id').all()).results).toEqual(before.results);
  expect((await env.DB.prepare('PRAGMA foreign_key_check').all()).results).toEqual([]);
  expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM agent_keys').first()).toEqual({ count: 7 });
  expect(await env.DB.prepare("SELECT role, is_admin FROM api_keys WHERE id = 'agent-0'").first()).toEqual({ role: 'admin', is_admin: 1 });
  expect((await SELF.fetch('https://test.local/__test/legacy-admin', { headers: adminHeaders })).status).toBe(200);
  expect((await SELF.fetch('https://test.local/api/keys', { headers: adminHeaders })).status).toBe(200);
  expect((await SELF.fetch('https://test.local/__test/legacy-admin', {
    headers: { Authorization: 'Bearer old-bearer-1' },
  })).status).toBe(403);
  for (let i = 0; i < 7; i++) {
    const response = await SELF.fetch('https://test.local/api/agents/me', { headers: { Authorization: `Bearer old-bearer-${i}` } });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ id: `agent-${i}`, agent_key_id: expect.any(String) });
  }
});
