// Worker tests for the boss key directory agents pin from: scope, revocation and labels.
// Covers real D1 rows through SELF.fetch; depends on cloudflare:test and the shared seed helpers.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, createAgentAuth, seedBossToken, seedDatabase } from '../test-helpers';
import type { BossKeysView } from './agent-boss-keys';

const url = 'https://test.local/api/agents/me/boss-keys';

async function addKey(id: string, bossId: string, kind: string, revoked = false): Promise<void> {
  const client = `${id}-client`;
  await env.DB.prepare("INSERT INTO boss_clients (id, boss_id, kind, label) VALUES (?, ?, ?, ?)")
    .bind(client, bossId, kind, `${kind} of ${bossId}`).run();
  const token = await env.DB.prepare("INSERT INTO boss_tokens (boss_id, label, token_hash, client_id) VALUES (?, 'k', ?, ?) RETURNING id")
    .bind(bossId, `hash-${id}`, client).first<{ id: string }>();
  await env.DB.prepare(`INSERT INTO boss_signing_keys (id, boss_id, boss_token_id, algorithm, client_kind,
      public_key, client_id, revoked_at) VALUES (?, ?, ?, 'ES256', ?, ?, ?, ?)`)
    .bind(id, bossId, token?.id, kind, `pub-${id}`, client, revoked ? '2026-11-28 00:00:00' : null).run();
}

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Admin Boss', 'admin', 'keys-admin-token', 'keys-admin');
  await seedBossToken('Granted Manager', 'manager', 'keys-granted-token', 'keys-granted');
  await seedBossToken('Other Manager', 'manager', 'keys-other-token', 'keys-other');
  await createAgentAuth('keys-agent', 'keys-agent-api-key');
  await env.DB.prepare("INSERT INTO boss_agent_access (boss_id, agent_id) VALUES ('keys-granted', 'keys-agent')").run();
  await addKey('key-admin-ios', 'keys-admin', 'ios');
  await addKey('key-admin-old', 'keys-admin', 'ios', true);
  await addKey('key-granted-mac', 'keys-granted', 'macos');
  await addKey('key-other-ios', 'keys-other', 'ios');
});

async function directory(headers: Record<string, string>): Promise<BossKeysView[]> {
  const response = await SELF.fetch(url, { headers });
  expect(response.status).toBe(200);
  expect(response.headers.get('Cache-Control')).toBe('no-store');
  return ((await response.json()) as { bosses: BossKeysView[] }).bosses;
}

it('lists admins and granted bosses with their keys, never a boss without access', async () => {
  const bosses = await directory(await createAgentAuth('keys-agent', 'keys-agent-api-key'));
  const ids = bosses.map(boss => boss.boss_id);
  expect(ids).toContain('keys-admin');
  expect(ids).toContain('keys-granted');
  expect(ids).not.toContain('keys-other');
  const granted = bosses.find(boss => boss.boss_id === 'keys-granted');
  expect(granted?.keys).toEqual([expect.objectContaining({
    key_id: 'key-granted-mac', public_key: 'pub-key-granted-mac', client_kind: 'macos',
    label: 'macos of keys-granted', revoked_at: null,
  })]);
});

it('returns a revoked key with its revocation time so an agent can stop trusting it', async () => {
  const admin = (await directory(authHeaders())).find(boss => boss.boss_id === 'keys-admin');
  const revoked = admin?.keys.find(key => key.key_id === 'key-admin-old');
  expect(revoked?.revoked_at).toEqual(expect.any(String));
  expect(admin?.keys.find(key => key.key_id === 'key-admin-ios')?.revoked_at).toBeNull();
});

it('refuses a request without an agent credential', async () => {
  expect((await SELF.fetch(url)).status).toBe(401);
});
