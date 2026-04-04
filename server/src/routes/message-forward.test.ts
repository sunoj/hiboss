// Tests for shared message forwarding helpers.
// Covers channel validation and successful forward persistence with attachment metadata.
// Depends on cloudflare:test env, seeded D1 state, and mocked global fetch.

import { env } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';
import type { MessageRow } from '../types';
import { forwardMessage, validateForwardChannel } from './message-forward';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(async () => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  await env.DB.prepare('DELETE FROM channel_configs WHERE agent_id = ? AND channel = ?').bind(getTestAgentId(), 'telegram').run();
  await env.DB.prepare("DELETE FROM messages WHERE reply_to LIKE 'forward-helper-%'").run();
  await env.DB.prepare("DELETE FROM messages WHERE id LIKE 'forward-helper-%'").run();
});

describe('validateForwardChannel', () => {
  it('accepts telegram and discord only', () => {
    expect(validateForwardChannel('telegram')).toBe('telegram');
    expect(validateForwardChannel('discord')).toBe('discord');
    expect(validateForwardChannel('api')).toBeNull();
  });
});

describe('forwardMessage', () => {
  it('delivers to telegram and persists forwarded metadata', async () => {
    const fileUrl = 'https://files.test/review.pdf';
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind(getTestAgentId(), JSON.stringify({ chat_id: 'chat-1', bot_token: 'telegram-token' })).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'async', 'discord', ?, 'sent', 'normal', ?)"
    ).bind('forward-helper-source', getTestAgentId(), 'Needs review', JSON.stringify({ file_url: fileUrl })).run();

    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 4242 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const original = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind('forward-helper-source').first<MessageRow>();
    expect(original).toBeTruthy();
    const forwarded = await forwardMessage(env, original as MessageRow, 'telegram');

    expect(forwarded.body).toBe('[Forwarded from discord] Needs review');
    expect(forwarded.channel).toBe('telegram');
    expect(forwarded.status).toBe('delivered');
    expect(forwarded.type).toBe('forwarded');
    expect(forwarded.reply_to).toBe('forward-helper-source');

    const stored = await env.DB
      .prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(forwarded.id)
      .first<{ metadata: string | null }>();
    const metadata = JSON.parse(stored?.metadata ?? '{}') as Record<string, unknown>;
    expect(metadata.file_url).toBe(fileUrl);
    expect(metadata.telegram_message_id).toBe(4242);
  });
});
