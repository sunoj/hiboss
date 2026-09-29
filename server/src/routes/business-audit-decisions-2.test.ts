// Decision integrity regressions for cron, option streams, and signed webhooks.
// Covers queued defaults, answer provenance, Discord replay, and Telegram chat binding.
// Depends on SELF, seeded D1 fixtures, scheduled delivery, and option expiry.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { handleScheduled } from '../scheduled';
import { expireMessageOptions } from './message-options';

const base = 'https://test.local';
const agent = getTestAgentId();
const token = 'decision-audit-stream-token';
const bossHeaders = { Authorization: `Bearer ${token}` };
const fresh = (name: string) => `decision-${name}-${crypto.randomUUID()}`;

async function option(id: string, defaults = false): Promise<MessageRow> {
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose', 'sent', ?, ?)`)
    .bind(id, agent, JSON.stringify({ options: ['Yes', 'No'], ...(defaults ? { default_option: 'No' } : {}) }),
      new Date(Date.now() + 60_000).toISOString()).run();
  const row = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!row) throw new Error('option fixture missing');
  return row;
}

async function answerCount(id: string): Promise<number> {
  const row = await env.DB.prepare('SELECT COUNT(*) AS total FROM messages WHERE reply_to = ?')
    .bind(id).first<{ total: number }>();
  return row?.total ?? 0;
}

async function seedTelegramChats(owner: string, inboundChat: string, otherChat: string): Promise<{ parent: string; local: string }> {
  const provider = fresh('f14-provider');
  const destination = fresh('f14-destination');
  await env.DB.prepare("INSERT INTO bosses (id, name, role, telegram_user_id) VALUES (?, ?, 'manager', ?)")
    .bind(owner, owner, owner).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(owner, agent).run();
  await env.DB.prepare("INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'telegram', ?)")
    .bind(fresh('f14-config'), agent, JSON.stringify({ chat_id: otherChat, bot_token: 'synthetic' })).run();
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES (?, 'telegram', ?, ?)")
    .bind(provider, provider, JSON.stringify({ bot_token: 'synthetic' })).run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES (?, ?, 'telegram_chat', ?, ?, ?)")
    .bind(destination, owner, provider, JSON.stringify({ chat_id: inboundChat }), destination).run();
  await env.DB.prepare('INSERT INTO inbound_routes (id, destination_id, target_agent_id) VALUES (?, ?, ?)')
    .bind(fresh('f14-route'), destination, agent).run();
  const parent = fresh('f14-parent');
  const local = fresh('f14-local');
  for (const [id, body, messageId] of [[parent, 'Question', 901], [local, 'Local', 902]] as const) {
    await env.DB.prepare(`INSERT INTO messages
      (id, agent_id, direction, mode, channel, body, status, metadata)
      VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', ?, 'delivered', ?)`)
      .bind(id, agent, body, JSON.stringify({ telegram_message_id: messageId })).run();
  }
  return { parent, local };
}

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('Decision stream boss', 'manager', token, fresh('stream-boss'));
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, agent).run();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('decision integrity: scheduled and webhook paths', () => {
  it('F19 queued delivery preserves a resolved default and does not default twice', async () => {
    const control = await option(fresh('f19-control'), true);
    await expireMessageOptions(env as Env, agent, control);
    expect(await answerCount(control.id)).toBe(1);
    expect((await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(control.id)
      .first<{ status: string }>())?.status).toBe('replied');
    const target = await option(fresh('f19-target'), true);
    await env.DB.prepare(`UPDATE messages SET expires_at = datetime('now', '-1 minute') WHERE id = ?`)
      .bind(target.id).run();
    await env.DB.prepare(`INSERT INTO delivery_queue
      (id, message_id, agent_id, channel, config, scheduled_at)
      VALUES (?, ?, ?, 'api', '{}', datetime('now', '-1 minute'))`)
      .bind(fresh('f19-queue'), target.id, agent).run();
    expect(await answerCount(target.id)).toBe(0);
    await handleScheduled(env as Env);
    expect(await answerCount(target.id)).toBe(1);
    expect((await env.DB.prepare('SELECT status FROM delivery_queue WHERE message_id = ?').bind(target.id)
      .first<{ status: string }>())?.status).toBe('delivered');
    const firstStatus = (await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(target.id)
      .first<{ status: string }>())?.status;
    await handleScheduled(env as Env);
    expect({ firstStatus, answersAfterSecondRun: await answerCount(target.id) })
      .toEqual({ firstStatus: 'replied', answersAfterSecondRun: 1 });
  });

  it('F20 option stream identifies auto-default as a system answer', async () => {
    const id = fresh('f20');
    const row = await option(id, true);
    const response = await SELF.fetch(`${base}/api/boss/stream?options=true`, { headers: bossHeaders });
    expect(response.status).toBe(200);
    const reader = response.body?.getReader();
    if (!reader) throw new Error('option stream missing');
    try {
      const first = new TextDecoder().decode((await reader.read()).value);
      expect(first).toContain(id);
      await expireMessageOptions(env as Env, agent, row);
      const persisted = await env.DB.prepare('SELECT metadata FROM messages WHERE reply_to = ?')
        .bind(id).first<{ metadata: string }>();
      expect(JSON.parse(persisted?.metadata ?? '{}')).toMatchObject({ auto_default: true });
      const resolved = new TextDecoder().decode((await reader.read()).value);
      expect(resolved).toContain(`"id":"${id}"`);
      expect(resolved).toContain('"answer":"No"');
      expect(resolved).not.toContain('"source":"api"');
    } finally {
      await reader.cancel();
    }
  });

  it('F13 Discord /msg rejects replay of a signed interaction', async () => {
    const channel = fresh('f13-channel');
    const user = fresh('f13-user');
    const boss = fresh('f13-boss');
    const bodyText = fresh('f13-body');
    const previousKey = env.DISCORD_PUBLIC_KEY;
    await env.DB.prepare("INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'discord', ?)")
      .bind(fresh('f13-config'), agent, JSON.stringify({ channel_id: channel, bot_token: 'synthetic' })).run();
    await env.DB.prepare("INSERT INTO bosses (id, name, role, discord_user_id) VALUES (?, ?, 'manager', ?)")
      .bind(boss, boss, user).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, agent).run();
    const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
    env.DISCORD_PUBLIC_KEY = Array.from(new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey)))
      .map(byte => byte.toString(16).padStart(2, '0')).join('');
    const payload = JSON.stringify({ id: fresh('f13-interaction'), type: 2, channel_id: channel,
      member: { user: { id: user } }, data: { name: 'msg', options: [{ name: 'message', value: bodyText }] } });
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = Array.from(new Uint8Array(await crypto.subtle.sign('Ed25519', keys.privateKey,
      new TextEncoder().encode(timestamp + payload)))).map(byte => byte.toString(16).padStart(2, '0')).join('');
    const send = () => SELF.fetch(`${base}/api/webhooks/discord-interactions`, { method: 'POST', body: payload,
      headers: { 'Content-Type': 'application/json', 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature } });
    try {
      expect((await send()).status).toBe(200);
      expect((await env.DB.prepare('SELECT COUNT(*) AS total FROM messages WHERE body = ?').bind(bodyText)
        .first<{ total: number }>())?.total).toBe(1);
      await send();
      expect((await env.DB.prepare('SELECT COUNT(*) AS total FROM messages WHERE body = ?').bind(bodyText)
        .first<{ total: number }>())?.total).toBe(1);
    } finally {
      env.DISCORD_PUBLIC_KEY = previousKey;
    }
  });

  it.each(['reply', 'reaction'])('F14 Telegram %s stays bound to the originating chat', async (scenario) => {
    const key = fresh('f14-key');
    const owner = fresh('f14-boss');
    const inboundChat = fresh('f14-inbound');
    const otherChat = fresh('f14-other');
    const previousSecret = env.TELEGRAM_WEBHOOK_SECRET;
    const previousMode = env.DESTINATIONS_MODE;
    env.TELEGRAM_WEBHOOK_SECRET = key;
    env.DESTINATIONS_MODE = 'on';
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true,"result":{}}', { status: 200 })));
    try {
      const { parent, local } = await seedTelegramChats(owner, inboundChat, otherChat);
      const send = (chat: string, replyId: number, body: string, update: number) => SELF.fetch(`${base}/api/webhooks/telegram`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': key },
        body: JSON.stringify({ update_id: update, message: { message_id: update, chat: { id: chat },
          from: { id: owner }, text: body, reply_to_message: { message_id: replyId } } }),
      });
      const reaction = (messageId: number) => SELF.fetch(`${base}/api/webhooks/telegram`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': key },
        body: JSON.stringify({ message_reaction: { chat: { id: otherChat }, message_id: messageId,
          user: { id: owner, first_name: 'Boss' }, new_reaction: [{ type: 'emoji', emoji: '👍' }] } }),
      });
      if (scenario === 'reply') {
        const updateBase = Math.floor(Date.now() / 1000);
        const control = await send(inboundChat, 901, fresh('f14-good'), updateBase);
        expect(control.status).toBe(201);
        expect((await control.json() as { reply_to: string }).reply_to).toBe(parent);
        const wrong = await send(otherChat, 901, fresh('f14-wrong'), updateBase + 1);
        if (wrong.status === 201) {
          expect((await wrong.json() as { reply_to: string | null }).reply_to).toBeNull();
        } else {
          expect(wrong.status).toBeGreaterThanOrEqual(400);
        }
      } else {
        expect((await reaction(902)).status).toBe(200);
        const localRow = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?').bind(local)
          .first<{ metadata: string }>();
        expect(JSON.parse(localRow?.metadata ?? '{}').reactions).toHaveLength(1);
        await reaction(901);
        const original = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?').bind(parent)
          .first<{ metadata: string }>();
        expect(JSON.parse(original?.metadata ?? '{}').reactions).toBeUndefined();
      }
    } finally {
      env.TELEGRAM_WEBHOOK_SECRET = previousSecret;
      env.DESTINATIONS_MODE = previousMode;
    }
  });
});
