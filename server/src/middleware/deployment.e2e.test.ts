// Exercises Worker-first rollout and schema recovery through SELF and real D1.
// Depends on legacy fixtures and migration 0045; no production database access.
import { env, SELF } from 'cloudflare:test';
import { expect, it } from 'vitest';
import { authHeaders, seedDatabase, seedBossToken } from '../test-helpers';
import migration from '../../migrations/0045_agent_keys.sql?raw';

it('keeps agent and dual boss auth available before migration, then honors migrated revocation', async () => {
  await seedDatabase();
  await seedBossToken('Deployment boss', 'admin', 'deployment-boss');
  await env.DB.prepare('DROP TABLE agent_keys').run();
  await env.DB.prepare('ALTER TABLE api_keys DROP COLUMN is_admin').run();
  const response = await SELF.fetch('https://test.local/api/agents/me', { headers: authHeaders() });
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ id: 'test-agent-id', agent_key_id: null });
  for (const headers of [authHeaders(), { Authorization: 'Bearer deployment-boss' }]) {
    expect((await SELF.fetch('https://test.local/api/sessions', { headers })).status).toBe(200);
  }
  for (const path of ['/api/agents/me', '/api/sessions']) {
    expect((await SELF.fetch(`https://test.local${path}`, {
      headers: { Authorization: 'Bearer invalid-deployment-token' },
    })).status).toBe(401);
  }
  expect(await env.DB.prepare('SELECT last_used_at FROM api_keys WHERE id = ?')
    .bind('test-agent-id').first()).toEqual({ last_used_at: expect.any(String) });
  const statements = migration.replace(/^--.*$/gm, '').split(';').map(sql => sql.trim()).filter(Boolean);
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
  const migrated = await SELF.fetch('https://test.local/api/agents/me', { headers: authHeaders() });
  expect(migrated.status).toBe(200);
  expect(await migrated.json()).toMatchObject({ id: 'test-agent-id', agent_key_id: expect.any(String) });
  await env.DB.prepare("UPDATE agent_keys SET revoked_at = datetime('now')").run();
  for (const path of ['/api/agents/me', '/api/sessions']) {
    expect((await SELF.fetch(`https://test.local${path}`, { headers: authHeaders() })).status).toBe(401);
  }
});
