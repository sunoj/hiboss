// Verifies destination inbound routes override legacy routes deterministically.
// Depends on real D1 storage, webhook lookup, and destination pattern matching.
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedDatabase } from '../../test-helpers';
import { findEnabledChannelConfig } from '../../routes/webhook-helpers';
import { findInboundRoute } from '../inbound';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT INTO api_keys (id, name, key_hash) VALUES ('new-agent', 'new-agent', 'new-hash')").run();
  await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES ('ib', 'Inbound', 'admin')").run();
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('ip', 'telegram', 'Bot', '{\"bot_token\":\"token\"}')").run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES ('id', 'ib', 'telegram_chat', 'ip', '{\"chat_id\":\"123\"}', 'Chat')").run();
  await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES ('test-agent-id', 'telegram', '{\"bot_token\":\"old-token\",\"chat_id\":\"123\"}')").run();
  await env.DB.prepare("INSERT INTO inbound_routes (id, destination_id, target_agent_id, priority) VALUES ('default', 'id', 'new-agent', 0)").run();
});
it('consults inbound routes before legacy channel configs', async () => {
  expect((await findEnabledChannelConfig(env, 'telegram', '123'))?.agent_id).toBe('new-agent');
});
it('honours pattern priority and skips invalid patterns', async () => {
  await env.DB.prepare("INSERT INTO inbound_routes (id, destination_id, pattern, target_agent_id, priority) VALUES ('pattern', 'id', '^deploy', 'test-agent-id', 10)").run();
  await env.DB.prepare("INSERT INTO inbound_routes (id, destination_id, pattern, target_agent_id, priority) VALUES ('invalid', 'id', '[', 'test-agent-id', 20)").run();
  expect((await findInboundRoute(env, 'telegram', '123', 'deploy now'))?.agent_id).toBe('test-agent-id');
  expect((await findInboundRoute(env, 'telegram', '123', 'hello'))?.agent_id).toBe('new-agent');
});
it('falls back to channel configs if no enabled destination route matches', async () => {
  await env.DB.prepare("UPDATE boss_destinations SET enabled = 0 WHERE id = 'id'").run();
  expect((await findEnabledChannelConfig(env, 'telegram', '123'))?.agent_id).toBe('test-agent-id');
});
