// Tests session inventory delta sync: changed, inserted, renamed and removed sessions since a cursor.
// Drives GET /api/boss/sessions through the Worker with real D1 triggers from migration 0070.
// Depends on cloudflare:test SELF, the shared test schema and seeded boss tokens.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { handleScheduled } from '../scheduled';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const TOKEN = 'hb_boss_session_delta_admin_00001';
const OLD = '2020-01-01 00:00:00';
type Inventory = { sessions: { id: string; label: string | null }[]; removed?: string[]; cursor: string };

async function inventory(query = ''): Promise<Inventory> {
  const response = await SELF.fetch(`http://localhost/api/boss/sessions?include_inactive=true${query}`,
    { headers: { Authorization: `Bearer ${TOKEN}` } });
  expect(response.status).toBe(200);
  return response.json() as Promise<Inventory>;
}

const ids = (page: Inventory) => page.sessions.map(session => session.id).filter(id => id.startsWith('delta-')).sort();
const run = (sql: string, ...binds: unknown[]) => env.DB.prepare(sql).bind(...binds).run();

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Delta Boss', 'admin', TOKEN, 'delta-boss');
  await run("INSERT INTO projects (id, slug, display_name) VALUES ('delta-project', 'delta', 'Delta')");
  for (const id of ['delta-a', 'delta-b', 'delta-c']) {
    await run("INSERT INTO sessions (id, agent_id, label, branch, project_id) VALUES (?, ?, 'x/main', 'main', ?)",
      id, getTestAgentId(), id === 'delta-a' ? 'delta-project' : null);
  }
  await run("UPDATE sessions SET updated_at = ? WHERE id LIKE 'delta-%'", OLD);
});

describe('GET /api/boss/sessions?updated_after', () => {
  it('returns the full inventory with a cursor, then an empty delta', async () => {
    const full = await inventory();
    expect(ids(full)).toEqual(['delta-a', 'delta-b', 'delta-c']);
    expect(full.removed).toBeUndefined();
    const delta = await inventory(`&updated_after=${encodeURIComponent(full.cursor)}`);
    expect(ids(delta)).toEqual([]);
    expect(delta.removed).toEqual([]);
  });

  it('returns changed, inserted, renamed and removed sessions since the cursor', async () => {
    const { cursor } = await inventory();
    await run("UPDATE sessions SET status = 'idle' WHERE id = 'delta-b'");
    await run("INSERT INTO sessions (id, agent_id, label) VALUES ('delta-d', ?, 'y/main')", getTestAgentId());
    await run("DELETE FROM sessions WHERE id = 'delta-c'");
    await run("UPDATE projects SET slug = 'delta-renamed' WHERE id = 'delta-project'");
    const delta = await inventory(`&updated_after=${encodeURIComponent(cursor)}`);
    expect(ids(delta)).toEqual(['delta-a', 'delta-b', 'delta-d']);
    expect(delta.sessions.find(session => session.id === 'delta-a')?.label).toBe('delta-renamed/main');
    expect(delta.removed).toEqual(['delta-c']);
  });

  it('drops a removal when the session registers again', async () => {
    const { cursor } = await inventory();
    await run("INSERT INTO sessions (id, agent_id, label) VALUES ('delta-c', ?, 'x/main')", getTestAgentId());
    const delta = await inventory(`&updated_after=${encodeURIComponent(cursor)}`);
    expect(ids(delta)).toContain('delta-c');
    expect(delta.removed).toEqual([]);
  });

  it('keeps removals for 30 days', async () => {
    await run(`INSERT INTO session_removals (session_id, agent_id, removed_at) VALUES
      ('delta-old', ?, datetime('now', '-31 days')), ('delta-recent', ?, datetime('now', '-29 days'))`,
    getTestAgentId(), getTestAgentId());
    await handleScheduled(env, 30);
    const kept = await env.DB.prepare("SELECT session_id FROM session_removals WHERE session_id IN ('delta-old', 'delta-recent')")
      .all<{ session_id: string }>();
    expect(kept.results.map(row => row.session_id)).toEqual(['delta-recent']);
  });

  it('refuses a cursor issued before the agent access of the boss changed', async () => {
    const { cursor } = await inventory();
    await run("INSERT INTO api_keys (id, name, key_hash) VALUES ('delta-new-agent', 'delta-new', 'delta-hash')");
    const response = await SELF.fetch(`http://localhost/api/boss/sessions?include_inactive=true&updated_after=${
      encodeURIComponent(cursor)}`, { headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(response.status).toBe(409);
  });

  it.each([
    ['?updated_after=2026-01-01%2000:00:00~0123456789abcdef'],
    ['?include_inactive=true&updated_after=2026-01-01%2000:00:00'],
    ['?include_inactive=true&updated_after=yesterday~0123456789abcdef'],
  ])('rejects %s', async (query) => {
    const response = await SELF.fetch(`http://localhost/api/boss/sessions${query}`,
      { headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(response.status).toBe(400);
  });
});
