// Replays the audit's duplicate-provider probe and verifies credential migration/API secrecy.
// Uses real Worker HTTP/D1 and Web Crypto, with only the external send adapter mocked.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, afterEach, expect, it, vi } from 'vitest';
import app from '../../index';
import { seedDatabase, seedBossToken } from '../../test-helpers';
import { dispatchDestinations } from '../dispatch';
import { credentialHash } from '../targets';
import * as adapters from '../adapters';
import type { MessageRow } from '../../types';
import migration from '../../../migrations/0042_provider_credentials.sql?raw';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('One', 'admin', 'credential-admin', 'one');
  await seedBossToken('Two', 'admin', 'credential-two', 'two');
});
afterEach(() => vi.restoreAllMocks());
async function beforeMigration(): Promise<void> {
  await env.DB.prepare('DROP INDEX idx_channel_providers_credential_hash').run();
  await env.DB.prepare('DROP INDEX idx_channel_providers_effective_credential').run();
  await env.DB.prepare('ALTER TABLE channel_providers DROP COLUMN credential_hash').run();
}
async function migrate(): Promise<void> {
  const statements = migration.replace(/^--.*$/gm, '').split(';').map(sql => sql.trim()).filter(Boolean);
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
}
async function message(): Promise<MessageRow> {
  const row = await env.DB.prepare(`INSERT INTO messages (agent_id, direction, mode, body)
    VALUES ('test-agent-id', 'agent_to_boss', 'async', 'credential probe') RETURNING *`).first<MessageRow>();
  if (!row) throw new Error('fixture failed');
  return row;
}
async function createProvider(credentials: Record<string, string>): Promise<Response> {
  const context = createExecutionContext();
  const response = await app.fetch(new Request('https://test/api/boss/providers', {
    method: 'POST', headers: { Authorization: 'Bearer credential-admin', 'Content-Type': 'application/json' },
    body: JSON.stringify({ provider: credentials.webhook_url ? 'discord' : 'telegram', label: 'Bot', credentials }),
  }), env, context);
  await waitOnExecutionContext(context);
  return response;
}

it('two providers, same token, two bosses, chat 506099557 produce one call and canonical row', async () => {
  await beforeMigration();
  for (const id of ['one', 'two']) {
    await env.DB.prepare(`INSERT INTO channel_providers (id, provider, label, credentials)
      VALUES (?, 'telegram', 'Bot', '{"bot_token":"same-secret"}')`).bind(id).run();
    await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, provider_id, kind, target, label)
      VALUES (?, ?, ?, 'telegram_chat', '{"chat_id":"506099557"}', 'Shared')`).bind(id, id, id).run();
  }
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  const sent = await message();
  await dispatchDestinations({ ...env, DESTINATIONS_MODE: 'on' }, sent);
  expect(spy).toHaveBeenCalledTimes(1);
  const claims = await env.DB.prepare('SELECT external_target, merged_into, status FROM message_deliveries WHERE message_id = ?').bind(sent.id).all();
  expect(claims.results.filter(row => row.external_target)).toHaveLength(1);
  expect(claims.results.filter(row => row.merged_into)).toHaveLength(1);
  expect(claims.results.every(row => row.status === 'sent')).toBe(true);
  const shadow = await message();
  await dispatchDestinations({ ...env, DESTINATIONS_MODE: 'shadow' }, shadow,
    [{ channel: 'telegram', config: { bot_token: 'same-secret', chat_id: '506099557' } }]);
  expect(spy).toHaveBeenCalledTimes(1);
  expect(await env.DB.prepare("SELECT id FROM audit_log WHERE action = 'destination_shadow' AND resource_id = ?").bind(shadow.id).first()).toBeNull();
  const shadowClaims = await env.DB.prepare('SELECT external_target FROM message_deliveries WHERE message_id = ? AND external_target IS NOT NULL').bind(shadow.id).all();
  expect(shadowClaims.results).toHaveLength(1);
  expect(shadowClaims.results[0].external_target).toBe(claims.results.find(row => row.external_target)?.external_target);
  await migrate();
  expect(await env.DB.prepare('SELECT id, credential_hash FROM channel_providers').all()).toMatchObject({ results: [{ id: 'one', credential_hash: await credentialHash('same-secret') }] });
  expect(await env.DB.prepare('SELECT DISTINCT provider_id FROM boss_destinations').all()).toMatchObject({ results: [{ provider_id: 'one' }] });
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM message_deliveries').first()).toEqual({ n: 4 });
  expect(await env.DB.prepare('PRAGMA foreign_key_check').all()).toMatchObject({ results: [] });
});

it('backfills SHA-256 byte and block boundaries with webhook precedence', async () => {
  await beforeMigration();
  const vectors = ['', 'abc', 'é🙂', ...[55, 56, 63, 64, 65, 119, 120, 200].map(n => 'x'.repeat(n))];
  for (const [index, token] of vectors.entries()) {
    await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES (?, 'discord', 'Vector', ?)")
      .bind(String(index), JSON.stringify({ webhook_url: token, bot_token: token ? 'ignored' : '' })).run();
  }
  await migrate();
  for (const [index, token] of vectors.entries()) {
    expect(await env.DB.prepare('SELECT credential_hash FROM channel_providers WHERE id = ?').bind(String(index)).first())
      .toEqual({ credential_hash: await credentialHash(token) });
  }
});

const duplicateCredentials: Record<string, string>[] = [
  { bot_token: 'duplicate-token' },
  { webhook_url: 'https://discord.com/api/webhooks/1/duplicate', bot_token: 'ignored-token' },
];
it.each(duplicateCredentials)('rejects duplicate effective credentials without exposing them', async credentials => {
  const responses = await Promise.all([createProvider(credentials), createProvider({ ...credentials, app_id: 'other-app' })]);
  expect(responses.map(response => response.status).sort()).toEqual([201, 409]);
  for (const response of responses) {
    const body = await response.text();
    expect(body).not.toContain('credential_hash');
    expect(body).not.toContain('duplicate-token');
    expect(body).not.toContain('https://discord.com');
    expect(body).not.toContain('ignored-token');
  }
  await expect(env.DB.prepare("INSERT INTO channel_providers (provider, label, credentials) VALUES ('discord', 'Bypass', ?)")
    .bind(JSON.stringify(credentials)).run()).rejects.toThrow('UNIQUE constraint failed');
});
