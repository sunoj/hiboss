// Integration tests for Telegram webhook command parsing and command-specific behavior.
// Covers /msg, /status, and regular text flows through POST /api/webhooks/telegram.
// Depends on cloudflare:test, shared seeded fixtures, and mocked global fetch for replies.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';

const TELEGRAM_SECRET = 'telegram-commands-secret';
const TELEGRAM_CHAT_ID = 'telegram-commands-chat';
const WEBHOOK_URL = 'https://test.local/api/webhooks/telegram';

beforeAll(async () => {
  await seedDatabase();
  env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(getTestAgentId(), 'telegram', JSON.stringify({ chat_id: TELEGRAM_CHAT_ID, bot_token: 'telegram-commands-bot' }))
    .run();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('Telegram command handling', () => {
  it('creates a message without the /msg prefix when a command entity is present', async () => {
    const res = await postTelegramWebhook({
      update_id: 7101,
      message: {
        message_id: 711,
        chat: { id: TELEGRAM_CHAT_ID, type: 'private' },
        text: '/msg telegram-commands:deploy-now',
        entities: [{ type: 'bot_command', offset: 0, length: 4 }],
        from: { id: 1, is_bot: false },
      },
    });

    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({ body: 'telegram-commands:deploy-now', direction: 'boss_to_agent' });
  });

  it('sends a session status response for /status commands', async () => {
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, status_text, last_seen_at) VALUES (?, ?, ?, ?, ?, datetime('now'))"
    ).bind('telegram-commands-session', getTestAgentId(), 'ops', 'working', 'checking build').run();

    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 901 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await postTelegramWebhook({
      update_id: 7102,
      message: {
        message_id: 712,
        chat: { id: TELEGRAM_CHAT_ID, type: 'private' },
        text: '/status',
        entities: [{ type: 'bot_command', offset: 0, length: 7 }],
        from: { id: 1, is_bot: false },
      },
    });

    expect(res.status).toBe(200);
    const sendPayload = JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body)) as { chat_id: string; text: string };
    expect(sendPayload.chat_id).toBe(TELEGRAM_CHAT_ID);
    expect(sendPayload.text).toContain('test-agent');
    expect(sendPayload.text).toContain('ops: working (checking build)');
  });

  it('keeps regular text messages unchanged when no command entity is present', async () => {
    const res = await postTelegramWebhook({
      update_id: 7103,
      message: {
        message_id: 713,
        chat: { id: TELEGRAM_CHAT_ID, type: 'private' },
        text: 'telegram-commands:plain-text',
        from: { id: 1, is_bot: false },
      },
    });

    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({ body: 'telegram-commands:plain-text', direction: 'boss_to_agent' });
  });
});

async function postTelegramWebhook(payload: Record<string, unknown>): Promise<Response> {
  return SELF.fetch(WEBHOOK_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Telegram-Bot-Api-Secret-Token': TELEGRAM_SECRET,
    },
    body: JSON.stringify(payload),
  });
}
