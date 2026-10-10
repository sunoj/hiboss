// Verifies Box author migration preserves existing boss items and retry records.
// Uses real D1 and HTTP responses with the two incremental Box migrations.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import boxMigration from '../migrations/0050_box_items.sql?raw';
import agentMigration from '../migrations/0052_box_item_agent.sql?raw';
import { OWNER, request } from './box-test-helpers';
import { seedBossToken, seedDatabase } from './test-helpers';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Box Owner', 'viewer', OWNER, OWNER);
});

// Each case starts from the pre-0052 schema; storage persists across cases in this file.
beforeEach(async () => {
  const drops = ['box_agent_idempotency', 'box_idempotency', 'box_items_fts', 'box_items'];
  await env.DB.batch(drops.map(table => env.DB.prepare(`DROP TABLE IF EXISTS ${table}`)));
  const statements = boxMigration.match(/CREATE TRIGGER[\s\S]*?END;|CREATE[\s\S]*?;/g) ?? [];
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
});

async function applyAgentMigration(): Promise<void> {
  const additions = agentMigration.replace(/^--.*$/gm, '').split(';')
    .map(sql => sql.trim()).filter(Boolean);
  await env.DB.batch(additions.map(sql => env.DB.prepare(sql)));
}

it('preserves pre-migration boss provenance, retries and nullable fields', async () => {
  await env.DB.prepare(`INSERT INTO box_items (id, boss_id, kind, text, source, created_at)
    VALUES ('bx_legacy', ?, 'text', 'legacy reference', 'cli', '2026-01-01T00:00:00.000Z')`)
    .bind(OWNER).run();
  await env.DB.prepare(`INSERT INTO box_idempotency (boss_id, idempotency_key, item_id)
    VALUES (?, 'agent:legacy-key', 'bx_legacy')`).bind(OWNER).run();
  await applyAgentMigration();
  const response = await request('/bx_legacy');
  expect(response.status).toBe(200);
  const item = await response.json();
  expect(item).toMatchObject({ id: 'bx_legacy', text: 'legacy reference', added_by: { kind: 'boss' },
    url: null, note: null, project: null, media_type: null, media_bytes: null, width: null,
    height: null, duration_ms: null, tags: [], has_media: false });
  const replay = await request('', 'POST', { text: 'ignored' }, OWNER,
    { 'Idempotency-Key': 'agent:legacy-key' });
  expect(replay.status).toBe(201);
  expect(await replay.json()).toEqual(item);
  const stored = await env.DB.prepare('SELECT agent_id FROM box_items WHERE id = ?')
    .bind('bx_legacy').first<{ agent_id: string | null }>();
  expect(stored?.agent_id).toBeNull();
});

it('keeps the boss retry schema and accepts main worker boss inserts after migration', async () => {
  const schema = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'box_idempotency'";
  const before = await env.DB.prepare(schema).first<{ sql: string }>();
  await applyAgentMigration();
  expect(await env.DB.prepare(schema).first()).toEqual(before);
  await env.DB.prepare(`INSERT INTO box_items (id, boss_id, kind, text, source, created_at)
    VALUES ('bx_rollback', ?, 'text', 'old worker reference', 'ios-share', ?)`)
    .bind(OWNER, '2026-01-01T00:00:00.000Z').run();
  const bossInsert = `INSERT INTO box_idempotency (boss_id, idempotency_key, item_id)
    VALUES (?, ?, ?) ON CONFLICT (boss_id, idempotency_key) DO NOTHING`;
  for (const id of ['bx_rollback', 'bx_ignored']) {
    await env.DB.prepare(bossInsert).bind(OWNER, 'rollback-key', id).run();
  }
  const record = await env.DB.prepare(`SELECT item_id FROM box_idempotency
    WHERE boss_id = ? AND idempotency_key = ?`).bind(OWNER, 'rollback-key').first();
  expect(record).toEqual({ item_id: 'bx_rollback' });
  const item = await env.DB.prepare('SELECT agent_id, source FROM box_items WHERE id = ?')
    .bind('bx_rollback').first();
  expect(item).toEqual({ agent_id: null, source: 'ios-share' });
});
