// Round-two regression: a Telegram reply answers the message it replies to, whatever the chat's agent.
// Covers a shared admin chat in destinations mode `on`, the boss-access condition, unquoted
// text answering a destination-delivered ask, and the unchanged routing of unmatched text.
// Depends on SELF, seeded D1 fixtures, and delivery rows.

import { env, SELF } from 'cloudflare:test';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedDatabase } from '../test-helpers';

const base = 'https://test.local';
const secret = 'reply-routing-secret';
const fresh = () => crypto.randomUUID().replaceAll('-', '');
const [agentA, agentB, chatX, chatY] = [fresh(), fresh(), fresh(), fresh()];
const admin = { id: fresh(), telegram: 'reply-routing-admin' };
const manager = { id: fresh(), telegram: 'reply-routing-manager' };
const destinationX = fresh();
let previousMode: string | undefined;
let update = Math.floor(Date.now() / 1000);

beforeAll(async () => {
  await seedDatabase();
  for (const [agent, chat] of [[agentA, chatX], [agentB, chatY]]) {
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)').bind(agent, agent, fresh()).run();
    await env.DB.prepare("INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'telegram', ?)")
      .bind(fresh(), agent, JSON.stringify({ chat_id: chat, bot_token: 'synthetic' })).run();
  }
  await env.DB.prepare("INSERT INTO bosses (id, name, role, telegram_user_id) VALUES (?, 'Admin', 'admin', ?), (?, 'Manager', 'manager', ?)")
    .bind(admin.id, admin.telegram, manager.id, manager.telegram).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(manager.id, agentA).run();
  const provider = fresh();
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES (?, 'telegram', ?, ?)")
    .bind(provider, provider, JSON.stringify({ bot_token: 'synthetic' })).run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES (?, ?, 'telegram_chat', ?, ?, 'X')")
    .bind(destinationX, admin.id, provider, JSON.stringify({ chat_id: chatX })).run();
  env.TELEGRAM_WEBHOOK_SECRET = secret;
  previousMode = env.DESTINATIONS_MODE;
  env.DESTINATIONS_MODE = 'on';
  vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true,"result":{}}', { status: 200 })));
});

afterAll(() => {
  env.DESTINATIONS_MODE = previousMode;
  vi.unstubAllGlobals();
});

/**
 * An open ask; `delivered` is the Telegram id it got in chat X, through metadata or a delivery row.
 * A destination send stores no message channel, as message-send does in mode `on`.
 */
async function ask(agent: string, delivered: { metadata?: number; delivery?: number }): Promise<string> {
  const id = fresh();
  const metadata = delivered.metadata ? { telegram_message_id: delivered.metadata, telegram_chat_id: chatX } : {};
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, metadata)
    VALUES (?, ?, 'agent_to_boss', 'blocking', ?, 'Drop the staging DB?', 'delivered', ?)`)
    .bind(id, agent, delivered.delivery ? null : 'telegram', JSON.stringify(metadata)).run();
  if (delivered.delivery) {
    await env.DB.prepare("INSERT INTO message_deliveries (message_id, destination_id, status, external_message_id) VALUES (?, ?, 'sent', ?)")
      .bind(id, destinationX, String(delivered.delivery)).run();
  }
  return id;
}

async function replyInX(from: string, replyTo: number | null, text: string): Promise<{ status: number; agent_id?: string; reply_to?: string | null }> {
  update += 1;
  const quoted = replyTo === null ? {} : { reply_to_message: { message_id: replyTo } };
  const response = await SELF.fetch(`${base}/api/webhooks/telegram`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': secret },
    body: JSON.stringify({ update_id: update, message: { message_id: update, chat: { id: chatX },
      from: { id: from }, text, ...quoted } }),
  });
  if (response.status !== 201) return { status: response.status };
  const row = await response.json() as { agent_id: string; reply_to: string | null };
  return { status: response.status, agent_id: row.agent_id, reply_to: row.reply_to };
}

async function status(id: string): Promise<string | undefined> {
  return (await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id).first<{ status: string }>())?.status;
}

describe('DL2: a Telegram reply answers the message it replies to', () => {
  it('links a reply to the chat agent own message (control)', async () => {
    const own = await ask(agentA, { metadata: 7601 });
    expect(await replyInX(admin.telegram, 7601, 'ok')).toEqual({ status: 201, agent_id: agentA, reply_to: own });
    expect(await status(own)).toBe('replied');
  });

  it("answers agent B's ask delivered to agent A's chat", async () => {
    const parent = await ask(agentB, { delivery: 7701 });
    expect(await replyInX(admin.telegram, 7701, 'yes, do it')).toEqual({ status: 201, agent_id: agentB, reply_to: parent });
    expect(await status(parent)).toBe('replied');
    const strays = await env.DB.prepare("SELECT COUNT(*) AS n FROM messages WHERE agent_id = ? AND body = 'yes, do it'")
      .bind(agentA).first<{ n: number }>();
    expect(strays?.n).toBe(0);
  });

  it('keeps chat routing when the replying boss has no access to the replied agent', async () => {
    const parent = await ask(agentB, { delivery: 7801 });
    expect(await replyInX(manager.telegram, 7801, 'not mine')).toEqual({ status: 201, agent_id: agentA, reply_to: null });
    expect(await status(parent)).toBe('delivered');
  });

  it("answers the chat agent's destination-delivered ask with unquoted text", async () => {
    const pending = await ask(agentA, { delivery: 7901 });
    expect(await replyInX(admin.telegram, null, 'go ahead')).toEqual({ status: 201, agent_id: agentA, reply_to: pending });
    expect(await status(pending)).toBe('replied');
  });
});
