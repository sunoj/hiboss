// Verifies Box author migration preserves existing boss items and retry records.
// Uses real D1 and HTTP responses with the two incremental Box migrations.
import { env } from 'cloudflare:test';
import { expect, it } from 'vitest';
import boxMigration from '../migrations/0050_box_items.sql?raw';
import agentMigration from '../migrations/0051_box_item_agent.sql?raw';
import { OWNER, request } from './box-test-helpers';
import { seedBossToken, seedDatabase } from './test-helpers';

it('preserves pre-migration boss provenance, retries and nullable fields', async () => {
  await seedDatabase();
  const statements = boxMigration.match(/CREATE TRIGGER[\s\S]*?END;|CREATE[\s\S]*?;/g) ?? [];
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
  await seedBossToken('Box Owner', 'viewer', OWNER, OWNER);
  await env.DB.prepare(`INSERT INTO box_items (id, boss_id, kind, text, source, created_at)
    VALUES ('bx_legacy', ?, 'text', 'legacy reference', 'cli', '2026-01-01T00:00:00.000Z')`)
    .bind(OWNER).run();
  await env.DB.prepare(`INSERT INTO box_idempotency (boss_id, idempotency_key, item_id)
    VALUES (?, 'agent:legacy-key', 'bx_legacy')`).bind(OWNER).run();
  const additions = agentMigration.replace(/^--.*$/gm, '').split(';')
    .map(sql => sql.trim()).filter(Boolean);
  await env.DB.batch(additions.map(sql => env.DB.prepare(sql)));
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
