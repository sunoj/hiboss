// Round-two ask integrity regressions across API, Telegram, and Discord writers.
// Covers one-answer races, unlinked late text, and ignored inserts.
// Depends on seeded D1 fixtures, SELF routes, and the real default resolver.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { seedBossToken, seedDatabase } from '../test-helpers';
import { expireMessageOptions } from './message-options';

const base = 'https://test.local';
const token = 'ask-r2-boss-token';
const telegramUser = 'ask-r2-telegram-user';
const discordUser = 'ask-r2-discord-user';
const fresh = () => crypto.randomUUID().replaceAll('-', '');
const bossHeaders = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
let bossId: string;

async function agentWithChannel(channel?: 'telegram' | 'discord'): Promise<{ agent: string; external: string }> {
  const agent = fresh();
  const external = fresh();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agent, agent, fresh()).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agent).run();
  if (channel) {
    const config = channel === 'telegram' ? { chat_id: external, bot_token: 'synthetic' }
      : { channel_id: external, bot_token: 'synthetic' };
    await env.DB.prepare('INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, ?, ?)')
      .bind(fresh(), agent, channel, JSON.stringify(config)).run();
  }
  return { agent, external };
}

async function ask(agent: string, channel: 'api' | 'telegram' | 'discord', metadata: Record<string, unknown> = {}): Promise<MessageRow> {
  const id = fresh();
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'blocking', ?, 'Choose', 'delivered', ?, ?)`)
    .bind(id, agent, channel, JSON.stringify(metadata), new Date(Date.now() + 60_000).toISOString()).run();
  const row = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!row) throw new Error('ask fixture missing');
  return row;
}

async function answers(id: string): Promise<{ body: string; reply_to: string | null }[]> {
  const rows = await env.DB.prepare("SELECT body, reply_to FROM messages WHERE reply_to = ? AND direction = 'boss_to_agent'")
    .bind(id).all<{ body: string; reply_to: string | null }>();
  return rows.results;
}

async function reply(id: string, body: string): Promise<Response> {
  return SELF.fetch(`${base}/api/boss/messages/${id}/reply`, {
    method: 'POST', headers: bossHeaders, body: JSON.stringify({ body }),
  });
}

async function telegram(chat: string, text: string, parentMessageId: number, updateId: number): Promise<Response> {
  return SELF.fetch(`${base}/api/webhooks/telegram`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': 'ask-r2-secret' },
    body: JSON.stringify({ update_id: updateId, message: { message_id: updateId, chat: { id: chat },
      from: { id: telegramUser }, text, reply_to_message: { message_id: parentMessageId } } }),
  });
}

beforeAll(async () => {
  await seedDatabase();
  bossId = await seedBossToken('Ask R2 boss', 'manager', token, fresh());
  await env.DB.prepare('UPDATE bosses SET telegram_user_id = ?, discord_user_id = ? WHERE id = ?')
    .bind(telegramUser, discordUser, bossId).run();
  env.TELEGRAM_WEBHOOK_SECRET = 'ask-r2-secret';
  env.DISCORD_WEBHOOK_SECRET = 'ask-r2-discord-secret';
});

afterEach(() => vi.unstubAllGlobals());

describe('one answer per ask across writers', () => {
  it('links Telegram text first and rejects a later button on the same ask', async () => {
    const { agent, external } = await agentWithChannel('telegram');
    const control = await ask(agent, 'telegram', { options: ['Yes', 'No'], telegram_message_id: 8101, telegram_chat_id: external });
    expect((await telegram(external, 'Yes', 8101, 8102)).status).toBe(201);
    expect(await answers(control.id)).toEqual([{ body: 'Yes', reply_to: control.id }]);
    const target = await ask(agent, 'telegram', { options: ['Yes', 'No'], telegram_message_id: 8201, telegram_chat_id: external });
    expect((await telegram(external, 'Yes', 8201, 8202)).status).toBe(201);
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true,"result":{}}', { status: 200 })));
    const button = await SELF.fetch(`${base}/api/webhooks/telegram`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': 'ask-r2-secret' },
      body: JSON.stringify({ callback_query: { id: fresh(), from: { id: telegramUser },
        data: `${target.id.slice(0, 12)}:No`, message: { message_id: 8201, chat: { id: external }, text: 'Choose' } } }),
    });
    expect(button.status).toBe(409);
    expect(await answers(target.id)).toEqual([{ body: 'Yes', reply_to: target.id }]);
  });

  it('returns 409 for a second boss API answer to an optionless blocking ask', async () => {
    const { agent } = await agentWithChannel();
    const control = await ask(agent, 'api');
    expect((await reply(control.id, 'First')).status).toBe(201);
    expect(await answers(control.id)).toEqual([{ body: 'First', reply_to: control.id }]);
    const target = await ask(agent, 'api');
    expect((await reply(target.id, 'Yes')).status).toBe(201);
    expect((await reply(target.id, 'No')).status).toBe(409);
    expect(await answers(target.id)).toEqual([{ body: 'Yes', reply_to: target.id }]);
  });

  it('stores Telegram text after an auto-default without linking it to the ask', async () => {
    const { agent, external } = await agentWithChannel('telegram');
    const control = await ask(agent, 'telegram', { options: ['Yes', 'No'], telegram_message_id: 8301, telegram_chat_id: external });
    expect((await telegram(external, 'Yes', 8301, 8302)).status).toBe(201);
    expect(await answers(control.id)).toHaveLength(1);
    const target = await ask(agent, 'telegram', { options: ['Yes', 'No'], default_option: 'No',
      telegram_message_id: 8401, telegram_chat_id: external });
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true,"result":{}}', { status: 200 })));
    await expireMessageOptions(env as Env, agent, target);
    expect(await answers(target.id)).toEqual([{ body: 'No', reply_to: target.id }]);
    const late = await telegram(external, 'I disagree', 8401, 8402);
    expect(late.status).toBe(201);
    expect((await late.json() as { reply_to: string | null }).reply_to).toBeNull();
    expect(await answers(target.id)).toHaveLength(1);
  });

  it('stores a late Discord text reply without linking it to an answered ask', async () => {
    const { agent, external } = await agentWithChannel('discord');
    const send = (text: string, parentId: string) => SELF.fetch(`${base}/api/webhooks/discord`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Webhook-Secret': 'ask-r2-discord-secret' },
      body: JSON.stringify({ channel_id: external, message: { id: fresh(), content: text,
        author: { id: discordUser }, message_reference: { message_id: parentId } } }),
    });
    const controlExternal = fresh();
    const control = await ask(agent, 'discord', { discord_message_id: controlExternal });
    expect((await send('Linked text', controlExternal)).status).toBe(201);
    expect(await answers(control.id)).toEqual([{ body: 'Linked text', reply_to: control.id }]);
    const targetExternal = fresh();
    const target = await ask(agent, 'discord', { discord_message_id: targetExternal });
    expect((await reply(target.id, 'Boss answer')).status).toBe(201);
    const late = await send('Late text', targetExternal);
    expect(late.status).toBe(201);
    expect((await late.json() as { reply_to: string | null }).reply_to).toBeNull();
    expect(await answers(target.id)).toEqual([{ body: 'Boss answer', reply_to: target.id }]);
  });

  it('stores Discord /msg without linking it to an answered ask', async () => {
    const { agent, external } = await agentWithChannel('discord');
    const previousKey = env.DISCORD_PUBLIC_KEY;
    const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
    env.DISCORD_PUBLIC_KEY = Array.from(new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey)))
      .map(byte => byte.toString(16).padStart(2, '0')).join('');
    const command = async (body: string): Promise<Response> => {
      const payload = JSON.stringify({ id: fresh(), type: 2, channel_id: external, member: { user: { id: discordUser } },
        data: { name: 'msg', options: [{ name: 'message', value: body }] } });
      const timestamp = String(Math.floor(Date.now() / 1000));
      const signature = Array.from(new Uint8Array(await crypto.subtle.sign('Ed25519', keys.privateKey,
        new TextEncoder().encode(timestamp + payload)))).map(byte => byte.toString(16).padStart(2, '0')).join('');
      return SELF.fetch(`${base}/api/webhooks/discord-interactions`, { method: 'POST', body: payload,
        headers: { 'Content-Type': 'application/json', 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature } });
    };
    try {
      const control = await ask(agent, 'discord');
      expect((await command('Linked control')).status).toBe(200);
      expect(await answers(control.id)).toEqual([{ body: 'Linked control', reply_to: control.id }]);
      const target = await ask(agent, 'discord');
      expect((await reply(target.id, 'Boss answer')).status).toBe(201);
      expect((await command('Late command')).status).toBe(200);
      const late = await env.DB.prepare('SELECT reply_to FROM messages WHERE agent_id = ? AND body = ?')
        .bind(agent, 'Late command').first<{ reply_to: string | null }>();
      expect(late?.reply_to).toBeNull();
      expect(await answers(target.id)).toEqual([{ body: 'Boss answer', reply_to: target.id }]);
    } finally {
      env.DISCORD_PUBLIC_KEY = previousKey;
    }
  });

  it('keeps an ask open when a trigger ignores its reply insert', async () => {
    const { agent } = await agentWithChannel();
    const control = await ask(agent, 'api', { options: ['Yes'] });
    expect((await reply(control.id, 'Yes')).status).toBe(201);
    expect(await answers(control.id)).toHaveLength(1);
    const target = await ask(agent, 'api', { options: ['Yes'] });
    const trigger = `ignore_${fresh()}`;
    await env.DB.prepare(`CREATE TRIGGER ${trigger} BEFORE INSERT ON messages
      WHEN NEW.reply_to = '${target.id}' BEGIN SELECT RAISE(IGNORE); END`).run();
    try {
      expect((await reply(target.id, 'Yes')).status).toBeGreaterThanOrEqual(500);
      expect(await answers(target.id)).toEqual([]);
      const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
        .bind(target.id).first<{ status: string }>();
      expect(parent?.status).toBe('delivered');
    } finally {
      await env.DB.prepare(`DROP TRIGGER ${trigger}`).run();
    }
  });
});
