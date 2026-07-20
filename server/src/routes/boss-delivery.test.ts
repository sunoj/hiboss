// Integration tests for boss delivery preferences during agent message sends.
// Covers legacy fallback, explicit mutes, routed delivery, and boss-agent notify.
// Depends on cloudflare:test, message route, and seeded D1 fixtures.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { seedDatabase } from '../test-helpers';
import type { Channel } from '../types';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('boss delivery preferences', () => {
  it('uses legacy delivery when only critical routing is configured', async () => {
    const requests = stubDeliveryFetch();
    const headers = await setupDeliveryAgent('boss-delivery-critical-only', 'hb_boss_delivery_critical_only');
    await seedChannel('boss-delivery-critical-only', 'telegram', { bot_token: 'tg-critical-only', chat_id: 'chat-critical-only' });
    await seedBoss('boss-delivery-critical-only', 'boss-delivery-critical-only-boss', {
      routing: { critical: ['discord'] },
    });

    const res = await sendMessage(headers, { body: 'normal fallback', channel: 'telegram' });
    await waitForNotifications();

    expect(res.status).toBe(201);
    expect(hasRequest(requests, 'api.telegram.org')).toBe(true);
    expect(hasRequest(requests, 'discord.local')).toBe(false);
    expect(hasRequest(requests, 'boss.local')).toBe(true);
  });

  it('mutes delivery and boss-agent notify for an explicit empty normal route', async () => {
    const requests = stubDeliveryFetch();
    const headers = await setupDeliveryAgent('boss-delivery-muted', 'hb_boss_delivery_muted');
    await seedChannel('boss-delivery-muted', 'discord', { webhook_url: 'https://discord.local/webhook/muted' });
    await seedBoss('boss-delivery-muted', 'boss-delivery-muted-boss', {
      routing: { normal: [] },
    });

    const res = await sendMessage(headers, { body: 'muted normal' });
    const message = await res.json() as { id: string };
    await waitForNotifications();

    expect(res.status).toBe(201);
    expect(requests).toHaveLength(0);
    await expect(messageChannel(message.id)).resolves.toBeNull();
  });

  it('delivers to discord only when normal routing selects discord', async () => {
    const requests = stubDeliveryFetch();
    const headers = await setupDeliveryAgent('boss-delivery-discord', 'hb_boss_delivery_discord');
    await seedChannel('boss-delivery-discord', 'discord', { webhook_url: 'https://discord.local/webhook/discord-only' });
    await seedChannel('boss-delivery-discord', 'telegram', { bot_token: 'tg-discord-only', chat_id: 'chat-discord-only' });
    await seedBoss('boss-delivery-discord', 'boss-delivery-discord-boss', {
      routing: { normal: ['discord'] },
    });

    const res = await sendMessage(headers, { body: 'discord only' });
    await waitForNotifications();

    expect(res.status).toBe(201);
    expect(hasRequest(requests, 'discord.local')).toBe(true);
    expect(hasRequest(requests, 'api.telegram.org')).toBe(false);
    expect(hasRequest(requests, 'boss.local')).toBe(false);
  });

  it('keeps legacy behavior when no routing is stored', async () => {
    const requests = stubDeliveryFetch();
    const headers = await setupDeliveryAgent('boss-delivery-no-routing', 'hb_boss_delivery_no_routing');
    await seedChannel('boss-delivery-no-routing', 'discord', { webhook_url: 'https://discord.local/webhook/no-routing' });
    await seedChannel('boss-delivery-no-routing', 'telegram', { bot_token: 'tg-no-routing', chat_id: 'chat-no-routing' });
    await seedBoss('boss-delivery-no-routing', 'boss-delivery-no-routing-boss', { quiet_hours: null });

    const res = await sendMessage(headers, { body: 'no routing', channel: 'telegram' });
    await waitForNotifications();

    expect(res.status).toBe(201);
    expect(hasRequest(requests, 'api.telegram.org')).toBe(true);
    expect(hasRequest(requests, 'discord.local')).toBe(false);
    expect(hasRequest(requests, 'boss.local')).toBe(true);
  });

  it('uses a configured priority from one boss when another boss omits it', async () => {
    const requests = stubDeliveryFetch();
    const headers = await setupDeliveryAgent('boss-delivery-multi', 'hb_boss_delivery_multi');
    await seedChannel('boss-delivery-multi', 'discord', { webhook_url: 'https://discord.local/webhook/multi' });
    await seedChannel('boss-delivery-multi', 'telegram', { bot_token: 'tg-multi', chat_id: 'chat-multi' });
    await seedBoss('boss-delivery-multi', 'boss-delivery-multi-critical', {
      routing: { critical: ['api'] },
    });
    await seedBoss('boss-delivery-multi', 'boss-delivery-multi-normal', {
      routing: { normal: ['telegram'] },
    });

    const res = await sendMessage(headers, { body: 'multi partial' });
    await waitForNotifications();

    expect(res.status).toBe(201);
    expect(hasRequest(requests, 'api.telegram.org')).toBe(true);
    expect(hasRequest(requests, 'discord.local')).toBe(false);
    expect(hasRequest(requests, 'boss.local')).toBe(false);
  });

  it('keeps a multi-boss mute when another boss omits normal routing', async () => {
    const requests = stubDeliveryFetch();
    const headers = await setupDeliveryAgent('boss-delivery-multi-muted', 'hb_boss_delivery_multi_muted');
    await seedChannel('boss-delivery-multi-muted', 'telegram', { bot_token: 'tg-multi-muted', chat_id: 'chat-multi-muted' });
    await seedBoss('boss-delivery-multi-muted', 'boss-delivery-multi-muted-critical', {
      routing: { critical: ['api'] },
    });
    await seedBoss('boss-delivery-multi-muted', 'boss-delivery-multi-muted-normal', {
      routing: { normal: [] },
    });

    const res = await sendMessage(headers, { body: 'multi muted normal', channel: 'telegram' });
    await waitForNotifications();
    const message = await res.json() as { id: string };

    expect(res.status).toBe(201);
    expect(requests).toHaveLength(0);
    await expect(messageChannel(message.id)).resolves.toBeNull();
  });
});

async function setupDeliveryAgent(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR REPLACE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  await env.DB.prepare('INSERT OR REPLACE INTO api_keys (id, name, key_hash, callback_url) VALUES (?, ?, ?, ?)')
    .bind(`${agentId}-boss-agent`, `${agentId}-boss-agent`, `${agentId}-boss-hash`, `https://boss.local/callback/${agentId}`)
    .run();
  return { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' };
}

async function seedChannel(agentId: string, channel: Channel, config: Record<string, unknown>): Promise<void> {
  await env.DB.prepare(
    'INSERT OR REPLACE INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, ?, ?, 1)'
  ).bind(`cfg-${agentId}-${channel}`, agentId, channel, JSON.stringify(config)).run();
}

async function seedBoss(agentId: string, bossId: string, preferences: Record<string, unknown>): Promise<void> {
  await env.DB.prepare(
    'INSERT OR REPLACE INTO bosses (id, name, role, agent_id, preferences) VALUES (?, ?, ?, ?, ?)'
  ).bind(bossId, `Boss ${bossId}`, 'manager', `${agentId}-boss-agent`, JSON.stringify(preferences)).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agentId)
    .run();
}

async function sendMessage(headers: Record<string, string>, body: Record<string, unknown>): Promise<Response> {
  return SELF.fetch('https://test.local/api/messages', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

function stubDeliveryFetch(): string[] {
  const requests: string[] = [];
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
    const url = input instanceof Request ? input.url : input.toString();
    requests.push(url);
    if (url.includes('discord')) {
      return new Response(JSON.stringify({ id: `discord-${requests.length}` }), { status: 200 });
    }
    return new Response(JSON.stringify({ ok: true, result: { message_id: requests.length } }), { status: 200 });
  }));
  return requests;
}

function hasRequest(requests: string[], pattern: string): boolean {
  return requests.some((url) => url.includes(pattern));
}

function waitForNotifications(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 25));
}

async function messageChannel(messageId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT channel FROM messages WHERE id = ?')
    .bind(messageId)
    .first<{ channel: string | null }>();
  return row?.channel ?? null;
}
