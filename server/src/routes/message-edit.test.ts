// Integration tests for agent message edits through PATCH /api/messages/:id.
// Covers body edits, ownership checks, audit logging, and combined status/body updates.
// Depends on cloudflare:test, D1 fixtures, and shared auth helpers.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const API_BASE = 'https://test.local/api/messages';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('PATCH /api/messages/:id', () => {
  it('updates an agent-owned message body after creation', async () => {
    const createRes = await SELF.fetch(API_BASE, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:create-body' }),
    });
    const created = await createRes.json() as { id: string };

    const editRes = await SELF.fetch(`${API_BASE}/${created.id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:updated-body' }),
    });

    expect(editRes.status).toBe(200);
    expect(await editRes.json()).toMatchObject({ id: created.id, body: 'message-edit:updated-body' });

    const stored = await env.DB.prepare('SELECT body FROM messages WHERE id = ?').bind(created.id).first<{ body: string }>();
    expect(stored?.body).toBe('message-edit:updated-body');
  });

  it('rejects body edits for non-agent_to_boss messages', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('message-edit-non-agent', getTestAgentId(), 'message-edit:boss-to-agent').run();

    const res = await SELF.fetch(`${API_BASE}/message-edit-non-agent`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:forbidden' }),
    });

    expect(res.status).toBe(403);
    expect(await res.text()).toBe('only agent_to_boss messages can be edited');
  });

  it('does not let a different agent edit another agent message', async () => {
    await createAgentHeaders('message-edit-owner', 'hb_message_edit_owner_key_000000');
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'api', ?, 'sent', 'normal', ?)"
    ).bind('message-edit-owned-by-other', 'message-edit-owner', 'message-edit:other-owner', getTestAgentId()).run();

    const res = await SELF.fetch(`${API_BASE}/message-edit-owned-by-other`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'delivered' }),
    });

    expect(res.status).toBe(403);
    expect(await res.text()).toBe('only message owner can update message');
  });

  it('writes an audit log entry when a message body is edited', async () => {
    const createRes = await SELF.fetch(API_BASE, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:audit-source' }),
    });
    const created = await createRes.json() as { id: string };

    const editRes = await SELF.fetch(`${API_BASE}/${created.id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:audit-updated' }),
    });
    expect(editRes.status).toBe(200);

    await new Promise((resolve) => setTimeout(resolve, 50));

    const audit = await env.DB
      .prepare("SELECT actor_type, actor_id, action, resource_id FROM audit_log WHERE action = 'message.edit' AND resource_id = ? ORDER BY created_at DESC LIMIT 1")
      .bind(created.id)
      .first<{ actor_type: string; actor_id: string; action: string; resource_id: string }>();

    expect(audit).toEqual({
      actor_type: 'agent',
      actor_id: getTestAgentId(),
      action: 'message.edit',
      resource_id: created.id,
    });
  });

  it('updates status and body in the same patch request', async () => {
    const createRes = await SELF.fetch(API_BASE, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:combined-source' }),
    });
    const created = await createRes.json() as { id: string };

    const res = await SELF.fetch(`${API_BASE}/${created.id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:combined-updated', status: 'delivered' }),
    });

    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({
      id: created.id,
      body: 'message-edit:combined-updated',
      status: 'delivered',
    });
  });

  it('edits Telegram media mirrors via caption updates', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    await env.DB.prepare(
      'INSERT OR REPLACE INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, ?, ?, 1)'
    ).bind(getTestAgentId(), 'telegram', JSON.stringify({ bot_token: 'tg-token', chat_id: 'chat-1' })).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'async', 'telegram', ?, 'delivered', 'normal', ?)"
    ).bind(
      'message-edit-telegram-caption',
      getTestAgentId(),
      'message-edit:caption-source',
      JSON.stringify({ telegram_message_id: 42, file_url: 'https://files.test/report.pdf' }),
    ).run();

    const res = await SELF.fetch(`${API_BASE}/message-edit-telegram-caption`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'message-edit:caption-updated' }),
    });

    expect(res.status).toBe(200);
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe('https://api.telegram.org/bottg-token/editMessageCaption');
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toMatchObject({
      chat_id: 'chat-1',
      message_id: 42,
      caption: '[test-agent] message-edit:caption-updated',
    });
  });
});

async function createAgentHeaders(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}
