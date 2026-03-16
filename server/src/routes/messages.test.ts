// Integration tests for /api/messages endpoints.
// Covers send, list, get, reply, patch, and poll flows.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('POST /api/messages', () => {
  it('creates a message with defaults', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Hello boss' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string; status: string; created_at: string };
    expect(data.id).toBeTruthy();
    expect(data.status).toBe('sent');
    expect(data.created_at).toBeTruthy();
  });

  it('rejects empty body', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects missing body', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
  });

  it('accepts priority and mode', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Urgent!', priority: 'high', mode: 'blocking' }),
    });
    expect(res.status).toBe(201);
  });
});

describe('GET /api/messages', () => {
  it('lists messages for agent', async () => {
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

  it('supports limit and offset', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?limit=1&offset=0', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[] };
    expect(data.messages.length).toBeLessThanOrEqual(1);
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
});

describe('PATCH /api/messages/:id', () => {
  it('updates message status', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Patch test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'read' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { status: string };
    expect(data.status).toBe('read');
  });

  it('rejects invalid status', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Invalid status test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'invalid' }),
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/messages/:id/react', () => {
  it('rejects empty emoji', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'React test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/react', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👀' }),
    });
    expect(res.status).toBe(404);
  });

  it('rejects react on non-telegram message', async () => {
    // Create a message with no channel (not telegram)
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'No channel msg' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👀' }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('telegram');
  });
});

describe('POST /api/messages with metadata', () => {
  it('stores file_url in metadata', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'See file', file_url: 'https://example.com/img.png' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    // Verify metadata contains file_url
    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { metadata: Record<string, unknown> | null };
    expect(msg.metadata?.['file_url']).toBe('https://example.com/img.png');
  });

  it('stores custom metadata', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'With meta', metadata: { task: 'test-123' } }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { metadata: Record<string, unknown> | null };
    expect(msg.metadata?.['task']).toBe('test-123');
  });

  it('accepts options as array', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: ['A', 'B', 'C'] }),
    });
    expect(res.status).toBe(201);
  });
});

describe('POST /api/messages with type', () => {
  it('stores message type', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Deploy done', type: 'task_update' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { type: string | null };
    expect(msg.type).toBe('task_update');
  });

  it('defaults type to text', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Plain message' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { type: string | null };
    expect(msg.type).toBe('text');
  });
});

describe('POST /api/messages/:id/poll', () => {
  it('returns 400 for non-blocking message', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Async msg', mode: 'async' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/poll`, {
      method: 'POST',
      headers: authHeaders(),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/poll', {
      method: 'POST',
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/messages idempotency', () => {
  it('returns 201 on first send with idempotency_key', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'test', idempotency_key: 'key-1' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as Record<string, unknown>;
    expect(data.id).toBeDefined();
  });

  it('returns 200 with same id on duplicate idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'first', idempotency_key: 'dup-key' }),
    });
    expect(res1.status).toBe(201);
    const data1 = await res1.json() as Record<string, unknown>;
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'second', idempotency_key: 'dup-key' }),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as Record<string, unknown>;
    expect(data2.id).toBe(data1.id);
  });

  it('creates new message with different idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'a', idempotency_key: 'key-a' }),
    });
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'b', idempotency_key: 'key-b' }),
    });
    expect(res1.status).toBe(201);
    expect(res2.status).toBe(201);
    const d1 = await res1.json() as Record<string, unknown>;
    const d2 = await res2.json() as Record<string, unknown>;
    expect(d1.id).not.toBe(d2.id);
  });

  it('always creates new message without idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'no key 1' }),
    });
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'no key 2' }),
    });
    expect(res1.status).toBe(201);
    expect(res2.status).toBe(201);
    const d1 = await res1.json() as Record<string, unknown>;
    const d2 = await res2.json() as Record<string, unknown>;
    expect(d1.id).not.toBe(d2.id);
  });
});
