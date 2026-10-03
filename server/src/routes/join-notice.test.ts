// Tests the status poll that delivers an approved agent key and notifies channels.
// Covers pending polls, one-time delivery, racing polls, deduplication, and key secrecy.
// Depends on cloudflare:test D1 fixtures and mocked Telegram and Discord senders.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

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
const DEVICE = 'join-notice-device';
const DEVICE_ID = 'd_join_notice';
const TOKEN = 'join-notice-token';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO devices (id, label) VALUES (?, ?)').bind(DEVICE_ID, DEVICE).run();
  await env.DB.prepare('INSERT INTO api_keys (id, name, device_id) VALUES (?, ?, ?)')
    .bind(AGENT_ID, NAME, DEVICE_ID).run();
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
  await env.DB.prepare('DELETE FROM join_requests WHERE device_label = ?').bind(DEVICE).run();
  telegramSend.mockClear();
  discordSend.mockClear();
});

const PROFILES = JSON.stringify([{ profile: 'claude', name: NAME }]);
const DELIVERY = JSON.stringify({ device_id: DEVICE_ID, profiles: [{ profile: 'claude', name: NAME, agent_id: AGENT_ID, key: KEY }] });

async function insertRequest(status: 'pending' | 'approved'): Promise<void> {
  await env.DB.prepare(`INSERT INTO join_requests (poll_token_hash, status, device_label, device_id, profiles, delivery)
    VALUES (?, ?, ?, ?, ?, ?)`)
    .bind(await hashApiKey(TOKEN), status, DEVICE, status === 'approved' ? DEVICE_ID : null, PROFILES,
      status === 'approved' ? DELIVERY : null).run();
}

function deliveredKeys(response: Record<string, unknown>): unknown[] {
  const profiles = response['profiles'] as Array<Record<string, unknown>> | undefined;
  return (profiles ?? []).map(profile => profile['key']).filter(Boolean);
}

describe('GET /api/join/status key-delivery notice', () => {
  it('notifies each channel once only after delivering the key, without including the key', async () => {
    await insertRequest('pending');
    expect(await pollStatus()).toMatchObject({ status: 'pending', profiles: [{ profile: 'claude', name: NAME }] });
    expect(telegramSend).not.toHaveBeenCalled();
    expect(discordSend).not.toHaveBeenCalled();

    await env.DB.prepare('UPDATE join_requests SET status = ?, device_id = ?, delivery = ? WHERE device_label = ?')
      .bind('approved', DEVICE_ID, DELIVERY, DEVICE).run();
    const delivered = await pollStatus();
    expect(delivered).toMatchObject({ status: 'approved', device_id: DEVICE_ID });
    expect(deliveredKeys(delivered)).toEqual([KEY]);
    await vi.waitFor(() => {
      expect(telegramSend).toHaveBeenCalledTimes(1);
      expect(discordSend).toHaveBeenCalledTimes(1);
    });
    const notice = `Device ${DEVICE} connected — keys delivered for ${NAME} (claude)`;
    expect(telegramSend).toHaveBeenCalledWith(expect.any(Object), notice, undefined);
    expect(discordSend).toHaveBeenCalledWith(expect.any(Object), notice, undefined);
    expect(notice).not.toContain(KEY);

    const repeated = await pollStatus();
    expect(repeated).toMatchObject({ status: 'approved', delivered: true });
    expect(deliveredKeys(repeated)).toEqual([]);
    expect(await env.DB.prepare('SELECT delivery FROM join_requests WHERE device_label = ?').bind(DEVICE).first('delivery')).toBeNull();
    expect(telegramSend).toHaveBeenCalledTimes(1);
    expect(discordSend).toHaveBeenCalledTimes(1);
  });

  it('delivers the key to exactly one of two racing polls', async () => {
    await insertRequest('approved');
    const responses = await Promise.all([pollStatus(), pollStatus()]);
    expect(responses.flatMap(deliveredKeys)).toEqual([KEY]);
    await vi.waitFor(() => {
      expect(telegramSend).toHaveBeenCalledTimes(1);
      expect(discordSend).toHaveBeenCalledTimes(1);
    });
  });

  it('returns the key and continues to Discord if Telegram sending fails', async () => {
    await insertRequest('approved');
    telegramSend.mockRejectedValueOnce(new Error('channel unavailable'));
    expect(deliveredKeys(await pollStatus())).toEqual([KEY]);
    await vi.waitFor(() => expect(discordSend).toHaveBeenCalledTimes(1));
  });
});

async function pollStatus(): Promise<Record<string, unknown>> {
  const response = await SELF.fetch(`https://test.local/api/join/status?token=${TOKEN}`);
  expect(response.status).toBe(200);
  return response.json() as Promise<Record<string, unknown>>;
}
