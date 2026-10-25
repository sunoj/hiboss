// Migration 0063 backfill: every existing push device is bound to the live token that keeps it pushing.
// Replays the migration's data statements over seeded devices with no token binding.
// Depends on seeded D1; all tokens and device tokens are fake fixtures.
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import migration from '../../migrations/0063_credential_issuers.sql?raw';
import { seedDatabase } from '../test-helpers';

beforeAll(seedDatabase);

async function token(id: string, bossId: string, clientId: string | null, createdAt: string, revoked = false): Promise<void> {
  await env.DB.prepare(`INSERT INTO boss_tokens (id, boss_id, label, token_hash, client_id, created_at, revoked_at)
    VALUES (?, ?, 'fixture', ?, ?, ?, ?)`).bind(id, bossId, `hash-${id}`, clientId, createdAt, revoked ? createdAt : null).run();
}

async function device(id: string, bossId: string, clientId: string | null, registeredAt?: string): Promise<void> {
  await env.DB.prepare(`INSERT INTO boss_devices (id, boss_id, device_token, bundle_id, environment, client_id, updated_at)
    VALUES (?, ?, ?, 'ai.hiboss.app', 'sandbox', ?, COALESCE(?, datetime('now')))`)
    .bind(id, bossId, `apns-${id}`, clientId, registeredAt ?? null).run();
}

async function replayMigration(): Promise<void> {
  const data = migration.replace(/^--.*$/gm, '').split(';').map(sql => sql.trim())
    .filter(sql => sql && !sql.startsWith('ALTER') && !sql.startsWith('CREATE INDEX'));
  await env.DB.batch(data.map(sql => env.DB.prepare(sql)));
}

it('binds a paired device to its client token, a client-less device to the newest client-less token, else nothing', async () => {
  await env.DB.prepare(`INSERT INTO bosses (id, name, role) VALUES ('bf-boss', 'Backfill', 'admin')`).run();
  await env.DB.prepare(`INSERT INTO boss_clients (id, boss_id, kind, label) VALUES
    ('bf-phone', 'bf-boss', 'ios', 'Phone'), ('bf-stale', 'bf-boss', 'ios', 'Stale')`).run();
  await token('bf-phone-old', 'bf-boss', 'bf-phone', '2026-01-01 00:00:00');
  await token('bf-phone-new', 'bf-boss', 'bf-phone', '2026-02-01 00:00:00');
  await token('bf-stale-token', 'bf-boss', 'bf-stale', '2026-01-01 00:00:00', true);
  await token('bf-loose-live', 'bf-boss', null, '2026-01-01 00:00:00');
  await token('bf-loose-revoked', 'bf-boss', null, '2026-03-01 00:00:00', true);
  await device('bf-paired', 'bf-boss', 'bf-phone');
  await device('bf-loose', 'bf-boss', null);
  await device('bf-silenced', 'bf-boss', 'bf-stale');
  await replayMigration();
  const rows = await env.DB.prepare("SELECT id, token_id FROM boss_devices WHERE boss_id = 'bf-boss' ORDER BY id")
    .all<{ id: string; token_id: string | null }>();
  expect(rows.results).toEqual([
    { id: 'bf-loose', token_id: 'bf-loose-live' },
    { id: 'bf-paired', token_id: 'bf-phone-new' },
    { id: 'bf-silenced', token_id: null },
  ]);
});

it('leaves a device registered before a later rotation token unbound', async () => {
  await env.DB.prepare(`INSERT INTO bosses (id, name, role) VALUES ('bf-rotated', 'Rotated', 'admin')`).run();
  await token('bf-r1', 'bf-rotated', null, '2026-01-01 00:00:00', true);
  await token('bf-r2', 'bf-rotated', null, '2026-02-10 00:00:00');
  await device('bf-lost', 'bf-rotated', null, '2026-01-15 00:00:00');
  await device('bf-current', 'bf-rotated', null, '2026-02-15 00:00:00');
  await replayMigration();
  const rows = await env.DB.prepare("SELECT id, token_id FROM boss_devices WHERE boss_id = 'bf-rotated' ORDER BY id")
    .all<{ id: string; token_id: string | null }>();
  expect(rows.results).toEqual([
    { id: 'bf-current', token_id: 'bf-r2' },
    { id: 'bf-lost', token_id: null },
  ]);
});
