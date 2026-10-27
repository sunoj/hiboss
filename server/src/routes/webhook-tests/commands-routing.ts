// Telegram command registration and owner-scoped pattern routing.
// Registers integration cases with shared root setup and a local routing seed.

import { env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, vi } from 'vitest';
import { testRequest } from '../../test-request';
import { authHeaders, getTestAgentId } from '../../test-helpers';
import { hashApiKey } from '../../middleware/auth';
import { telegramText, createdTelegram } from './support';

describe('POST /api/webhooks/telegram/register-commands', () => {
  it('registers Telegram bot commands through the Bot API', async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ ok: true, result: true }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await testRequest('POST', 'https://test.local/api/webhooks/telegram/register-commands',
      authHeaders(), { bot_token: 'telegram-register-token' });

    expect(res.status).toBe(201);
    const registerCall = fetchMock.mock.calls[0] as unknown as [RequestInfo | URL, RequestInit];
    expect(String(registerCall[0])).toContain('/setMyCommands');
    const payload = JSON.parse(String(registerCall[1].body)) as {
      commands: Array<{ command: string; description: string }>;
    };
    expect(payload.commands).toEqual([
      { command: 'msg', description: 'Send a message to the AI agent' },
      { command: 'status', description: 'Show agent session status' },
    ]);
  });
});

describe('Routing rules integration', () => {
  const targetAgentId = 'routing-target-agent';

  beforeAll(async () => {
    // Create a second agent for routing target
    const keyHash = await hashApiKey('hb_routing_target_key');
    await env.DB.prepare(
      'INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)'
    ).bind(targetAgentId, 'routing-target', keyHash).run();

    // Create a routing rule: messages containing "deploy" go to target agent
    await env.DB.prepare(
      "INSERT INTO routing_rules (owner_id, channel, pattern, target_agent_id, priority, enabled) VALUES " +
      "(?, 'telegram', 'deploy', ?, 10, 1)"
    ).bind(getTestAgentId(), targetAgentId).run();
  });

  it('routes telegram message to target agent when pattern matches', async () => {
    const data = await createdTelegram(telegramText('please deploy to production'));
    expect(data.agent_id).toBe(targetAgentId);
    expect(data.body).toBe('please deploy to production');
  });

  it('routes to default agent when no pattern matches', async () => {
    const data = await createdTelegram(telegramText('hello there'));
    expect(data.agent_id).toBe(getTestAgentId());
  });
});
