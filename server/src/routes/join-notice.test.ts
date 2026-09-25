// Tests the status poll that delivers an approved agent key and notifies channels.
// Covers pending polls, first delivery, repeat polls, deduplication, and key secrecy.
// Depends on cloudflare:test D1 fixtures and mocked Telegram and Discord senders.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';

vi.mock('../channels/telegram', async () => {
  const actual = await vi.importActual<typeof import('../channels/telegram')>('../channels/telegram');
  return { ...actual, sendTelegramMessage: vi.fn(async () => 101) };
});

vi.mock('../channels/discord', async () => {
  const actual = await vi.importActual<typeof import('../channels/discord')>('../channels/discord');
  return { ...actual, sendDiscordMessage: vi.fn(async () => ({ messageId: '101' })) };
});

import { sendTelegramMessage } from '../channels/telegram';
import { sendDiscordMessage } from '../channels/discord';

const telegramSend = vi.mocked(sendTelegramMessage);
const discordSend = vi.mocked(sendDiscordMessage);
const AGENT_ID = '12345678abcdef0123456789abcdef01';
const KEY = 'test-delivered-key';
const NAME = 'join-notice-agent';
const TOKEN = 'join-notice-token';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS join_requests (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, poll_token TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')), api_key_id TEXT REFERENCES api_keys(id), api_key TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))"
  ).run();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(AGENT_ID, NAME, 'join-notice-hash').run();
  await env.DB.prepare(
    'INSERT INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?), (?, ?, ?), (?, ?, ?), (?, ?, ?)'
  ).bind(
    getTestAgentId(), 'telegram', JSON.stringify({ chat_id: 'notice-chat', bot_token: 'notice-bot' }),
    getTestAgentId(), 'discord', JSON.stringify({ channel_id: 'notice-channel', bot_token: 'notice-token' }),
    AGENT_ID, 'telegram', JSON.stringify({ chat_id: 'notice-chat', bot_token: 'notice-bot' }),
    AGENT_ID, 'discord', JSON.stringify({ channel_id: 'notice-channel', bot_token: 'notice-token' }),
  ).run();
});

afterEach(async () => {
  await env.DB.prepare("DELETE FROM join_requests WHERE name = ?").bind(NAME).run();
  telegramSend.mockClear();
  discordSend.mockClear();
});

describe('GET /api/join/status key-delivery notice', () => {
  it('notifies each channel once only after delivering the key, without including the key', async () => {
    await env.DB.prepare('INSERT INTO join_requests (name, poll_token, status) VALUES (?, ?, ?)')
      .bind(NAME, TOKEN, 'pending').run();

    const pending = await pollStatus();
    expect(pending).toMatchObject({ status: 'pending' });
    expect(telegramSend).not.toHaveBeenCalled();
    expect(discordSend).not.toHaveBeenCalled();

    await env.DB.prepare('UPDATE join_requests SET status = ?, api_key_id = ?, api_key = ? WHERE poll_token = ?')
      .bind('approved', AGENT_ID, KEY, TOKEN).run();
    const delivered = await pollStatus();
    expect(delivered).toMatchObject({ status: 'approved', key: KEY, agent_id: AGENT_ID });
    await vi.waitFor(() => {
      expect(telegramSend).toHaveBeenCalledTimes(1);
      expect(discordSend).toHaveBeenCalledTimes(1);
    });
    const notice = `Agent ${NAME} (${AGENT_ID.slice(0, 8)}) connected — key delivered`;
    expect(telegramSend).toHaveBeenCalledWith(expect.any(Object), notice, undefined);
    expect(discordSend).toHaveBeenCalledWith(expect.any(Object), notice, undefined);
    expect(notice).not.toContain(KEY);

    const repeated = await pollStatus();
    expect(repeated).toMatchObject({ status: 'approved' });
    expect(repeated).not.toHaveProperty('key');
    expect(telegramSend).toHaveBeenCalledTimes(1);
    expect(discordSend).toHaveBeenCalledTimes(1);
  });

  it('sends one notice when two polls race to clear the key', async () => {
    await env.DB.prepare('INSERT INTO join_requests (name, poll_token, status, api_key_id, api_key) VALUES (?, ?, ?, ?, ?)')
      .bind(NAME, TOKEN, 'approved', AGENT_ID, KEY).run();

    const responses = await Promise.all([pollStatus(), pollStatus()]);
    expect(responses.some((response) => response['key'] === KEY)).toBe(true);
    await vi.waitFor(() => {
      expect(telegramSend).toHaveBeenCalledTimes(1);
      expect(discordSend).toHaveBeenCalledTimes(1);
    });
  });

  it('returns the key and continues to Discord if Telegram sending fails', async () => {
    await env.DB.prepare('INSERT INTO join_requests (name, poll_token, status, api_key_id, api_key) VALUES (?, ?, ?, ?, ?)')
      .bind(NAME, TOKEN, 'approved', AGENT_ID, KEY).run();
    telegramSend.mockRejectedValueOnce(new Error('channel unavailable'));

    expect(await pollStatus()).toMatchObject({ status: 'approved', key: KEY });
    await vi.waitFor(() => expect(discordSend).toHaveBeenCalledTimes(1));
  });
});

async function pollStatus(): Promise<Record<string, unknown>> {
  const response = await SELF.fetch(`https://test.local/api/join/status?token=${TOKEN}`);
  expect(response.status).toBe(200);
  return response.json() as Promise<Record<string, unknown>>;
}
