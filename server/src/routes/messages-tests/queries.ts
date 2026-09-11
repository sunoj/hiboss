// Message API regression suites extracted to keep each file bounded.
// Registers cases in messages.test.ts; depends on its shared database setup.
import { createAgentAuth } from './support';
import { env, SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId } from '../../test-helpers';

describe('GET /api/messages', () => {
  it('lists messages for agent', async () => {
    const created = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST', headers: authHeaders(), body: JSON.stringify({ body: 'List fixture' }),
    });
    expect(created.status).toBe(201);
    const res = await SELF.fetch('https://test.local/api/messages', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[]; total: number };
    expect(data.messages).toBeInstanceOf(Array);
    expect(data.total).toBeGreaterThan(0);
  });

  it('filters by direction', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?direction=agent_to_boss', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { direction: string }[] };
    for (const msg of data.messages) {
      expect(msg.direction).toBe('agent_to_boss');
    }
  });

  it('supports unread shortcut', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?unread=true', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
  });

  it('filters by priority', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?priority=high,critical', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { priority: string }[] };
    for (const msg of data.messages) {
      expect(['high', 'critical']).toContain(msg.priority);
    }
  });

  it('searches by body text', async () => {
    // Create a message with unique body
    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'UniqueSearchTerm42 in this message' }),
    });
    const res = await SELF.fetch('https://test.local/api/messages?search=UniqueSearchTerm42', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { body: string }[] };
    expect(data.messages.length).toBeGreaterThanOrEqual(1);
    for (const msg of data.messages) {
      expect(msg.body).toContain('UniqueSearchTerm42');
    }
  });

  it('search returns empty for no match', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?search=zzz_no_match_zzz', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[] };
    expect(data.messages.length).toBe(0);
  });

  it('supports limit and offset', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?limit=1&offset=0', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[] };
    expect(data.messages.length).toBeLessThanOrEqual(1);
  });

  it('includes session context on list rows', async () => {
    await env.DB.prepare(
      "INSERT INTO sessions (id, agent_id, label, branch, status) VALUES (?, ?, ?, ?, 'working')"
    ).bind('list-session-context', getTestAgentId(), 'List Session', 'feat/session-list').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'With session context', 'sent', 'normal', ?)"
    ).bind('list-session-context-message', getTestAgentId(), 'list-session-context').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'Without session context', 'sent', 'normal', NULL)"
    ).bind('list-null-session-message', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages?limit=100', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as {
      messages: {
        id: string;
        session_label?: string | null;
        session_branch?: string | null;
        session_status?: string | null;
      }[];
    };
    const sessionMessage = data.messages.find((message) => message.id === 'list-session-context-message');
    expect(sessionMessage?.session_label).toBe('List Session');
    expect(sessionMessage?.session_branch).toBe('feat/session-list');
    expect(sessionMessage?.session_status).toBe('working');

    const nullSessionMessage = data.messages.find((message) => message.id === 'list-null-session-message');
    expect(nullSessionMessage?.session_label).toBeNull();
    expect(nullSessionMessage?.session_branch).toBeNull();
    expect(nullSessionMessage?.session_status).toBeNull();
  });
});

describe('GET /api/messages/:id', () => {
  it('returns message with replies', async () => {
    // Create a message first
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'For get test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { id: string; body: string; replies: unknown[] };
    expect(data.id).toBe(id);
    expect(data.body).toBe('For get test');
    expect(data.replies).toBeInstanceOf(Array);
  });

  it('supports short ID prefix', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Short ID test' }),
    });
    const { id } = await createRes.json() as { id: string };
    const prefix = id.slice(0, 8);

    const res = await SELF.fetch(`https://test.local/api/messages/${prefix}`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { id: string };
    expect(data.id).toBe(id);
  });

  it('returns 404 for unknown id', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent-id', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/messages/:id/reply', () => {
  it('creates a reply to a message', async () => {
    // First insert a boss_to_agent message to reply to
    const agentId = getTestAgentId();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Boss says hi', 'sent', 'normal')"
    ).bind('reply-test-msg', agentId).run();

    const res = await SELF.fetch('https://test.local/api/messages/reply-test-msg/reply', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Agent replies' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { direction: string; reply_to: string; body: string };
    expect(data.direction).toBe('agent_to_boss');
    expect(data.reply_to).toBe('reply-test-msg');
    expect(data.body).toBe('Agent replies');
  });

  it('rejects empty reply body', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Test', 'sent', 'normal')"
    ).bind('reply-empty-msg', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/reply-empty-msg/reply', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown parent', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/reply', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Reply to nothing' }),
    });
    expect(res.status).toBe(404);
  });

  it('sets target_agent_id on agent-to-agent replies and exposes them to the original sender', async () => {
    const otherHeaders = await createAgentAuth('reply-agent-2', 'hb_test_key_reply_agent_2_000000');
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'api', 'Ping', 'sent', 'normal', ?, ?)"
    ).bind('reply-a2a-parent', getTestAgentId(), 'session-a2a-parent', 'reply-agent-2').run();

    const replyRes = await SELF.fetch('https://test.local/api/messages/reply-a2a-parent/reply', {
      method: 'POST',
      headers: otherHeaders,
      body: JSON.stringify({ body: 'Pong back' }),
    });
    expect(replyRes.status).toBe(201);
    const reply = await replyRes.json() as { id: string; direction: string; target_agent_id: string | null; target_session_id: string | null };
    expect(reply.direction).toBe('agent_to_agent');
    expect(reply.target_agent_id).toBe(getTestAgentId());
    expect(reply.target_session_id).toBe('session-a2a-parent');

    const storedReply = await env.DB.prepare(
      'SELECT target_agent_id, target_session_id FROM messages WHERE id = ?'
    ).bind(reply.id).first<{ target_agent_id: string | null; target_session_id: string | null }>();
    expect(storedReply?.target_agent_id).toBe(getTestAgentId());
    expect(storedReply?.target_session_id).toBe('session-a2a-parent');

    const senderListRes = await SELF.fetch('https://test.local/api/messages?direction=agent_to_agent', {
      headers: authHeaders(),
    });
    expect(senderListRes.status).toBe(200);
    const senderList = await senderListRes.json() as { messages: { id: string; body: string }[] };
    expect(senderList.messages.some((message) => message.id === reply.id && message.body === 'Pong back')).toBe(true);
  });
});
