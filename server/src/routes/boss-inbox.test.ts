// Tests for boss-inbox routes: agent-as-boss reads and replies to sub-agent messages.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const BOSS_KEY = 'hb_boss_key_0000000000000000';
const SUB_KEY = 'hb_sub_key_00000000000000000';
let bossAgentId: string;
let subAgentId: string;
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  // Create boss agent
  const bossHash = await hashApiKey(BOSS_KEY);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('boss-agent-id', 'boss-agent', bossHash).run();
  bossAgentId = 'boss-agent-id';
  // Create sub agent
  const subHash = await hashApiKey(SUB_KEY);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('sub-agent-id', 'sub-agent', subHash).run();
  subAgentId = 'sub-agent-id';
  // Create boss record linked to boss agent
  const bossRow = await env.DB
    .prepare('INSERT INTO bosses (name, role, agent_id) VALUES (?, ?, ?) RETURNING id')
    .bind('Boss Agent', 'admin', bossAgentId)
    .first<{ id: string }>();
  bossId = bossRow!.id;
});

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_KEY}`, 'Content-Type': 'application/json' };
}

function subHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${SUB_KEY}`, 'Content-Type': 'application/json' };
}

describe('GET /api/boss/inbox', () => {
  it('returns 403 for non-boss agent', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/inbox', { headers: authHeaders() });
    expect(res.status).toBe(403);
  });

  it('lists messages from sub-agents', async () => {
    // Sub-agent sends a message
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('msg-from-sub-1', subAgentId, 'Hello boss').run();

    const res = await SELF.fetch('http://localhost/api/boss/inbox', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[]; total: number };
    expect(data.total).toBeGreaterThanOrEqual(1);
    const msg = data.messages.find((m: any) => m.id === 'msg-from-sub-1') as any;
    expect(msg).toBeDefined();
    expect(msg.body).toBe('Hello boss');
  });

  it('filters by unread', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/inbox?unread=true', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[] };
    for (const m of data.messages) {
      expect(['sent', 'delivered']).toContain((m as any).status);
    }
  });

  it('returns count only', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/inbox?count=true', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { total: number };
    expect(typeof data.total).toBe('number');
  });
});

describe('GET /api/boss/inbox/:id', () => {
  it('returns message with replies', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/inbox/msg-from-sub-1', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.id).toBe('msg-from-sub-1');
    expect(data.replies).toBeDefined();
  });

  it('returns 404 for non-existent message', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/inbox/nonexistent', { headers: bossHeaders() });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/boss/inbox/:id/reply', () => {
  it('boss-agent replies to sub-agent message', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/inbox/msg-from-sub-1/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Good work, proceed.' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.direction).toBe('boss_to_agent');
    expect(data.body).toBe('Good work, proceed.');
    expect(data.reply_to).toBe('msg-from-sub-1');
    expect(data.channel).toBe('api');
    expect(data.metadata?.boss_id).toBe(bossId);
  });

  it('marks parent as replied', async () => {
    const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind('msg-from-sub-1').first<{ status: string }>();
    expect(parent?.status).toBe('replied');
  });

  it('rejects empty body', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('msg-from-sub-2', subAgentId, 'Need help').run();

    const res = await SELF.fetch('http://localhost/api/boss/inbox/msg-from-sub-2/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });
});

describe('PATCH /api/boss/inbox/:id', () => {
  it('boss marks message as read', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('msg-from-sub-3', subAgentId, 'Status update').run();

    const res = await SELF.fetch('http://localhost/api/boss/inbox/msg-from-sub-3', {
      method: 'PATCH',
      headers: bossHeaders(),
      body: JSON.stringify({ status: 'read' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.status).toBe('read');
  });

  it('updates only the exact message id', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('msg-prefix', subAgentId, 'Primary').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('msg-prefix-extra', subAgentId, 'Sibling').run();

    const res = await SELF.fetch('http://localhost/api/boss/inbox/msg-prefix', {
      method: 'PATCH',
      headers: bossHeaders(),
      body: JSON.stringify({ status: 'read' }),
    });

    expect(res.status).toBe(200);

    const rows = await env.DB
      .prepare('SELECT id, status FROM messages WHERE id IN (?, ?)')
      .bind('msg-prefix', 'msg-prefix-extra')
      .all<{ id: string; status: string }>();
    const byId = new Map((rows.results ?? []).map((row) => [row.id, row.status]));

    expect(byId.get('msg-prefix')).toBe('read');
    expect(byId.get('msg-prefix-extra')).toBe('sent');
  });
});
