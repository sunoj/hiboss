// Message API regression suites extracted to keep each file bounded.
// Registers cases in messages.test.ts; depends on its shared database setup.
import { createAgentAuth } from './support';
import { env, SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId } from '../../test-helpers';
import { hashApiKey } from '../../middleware/auth';

describe('POST /api/messages/:id/forward', () => {
  it('rejects invalid target channels', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'discord', 'Needs review', 'sent', 'normal')"
    ).bind('forward-invalid-channel', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/forward-invalid-channel/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'api' }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('channel must be discord or telegram');
  });

  it('rejects forwarding when the caller does not own the message', async () => {
    const otherHeaders = await createAgentAuth('forward-owner', 'hb_test_key_forward_owner_000000');
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'telegram', 'Private', 'sent', 'normal', ?)"
    ).bind('forward-owner-only', 'forward-owner', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/forward-owner-only/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'discord' }),
    });
    expect(res.status).toBe(403);

    const ownerRes = await SELF.fetch('https://test.local/api/messages/forward-owner-only/forward', {
      method: 'POST',
      headers: otherHeaders,
      body: JSON.stringify({ channel: 'discord' }),
    });
    expect(ownerRes.status).not.toBe(403);
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

  it('rejects backward status transitions', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Backward transition test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const firstPatch = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'read' }),
    });
    expect(firstPatch.status).toBe(200);

    const secondPatch = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'delivered' }),
    });
    expect(secondPatch.status).toBe(400);
    expect(await secondPatch.text()).toContain('invalid status transition');
  });

  it('allows the target recipient to mark an a2a message read', async () => {
    const otherApiKey = 'hb_test_key_agent2_patch_000000';
    const otherKeyHash = await hashApiKey(otherApiKey);
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind('patch-agent-2', 'patch-agent-2', otherKeyHash)
      .run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Private', 'sent', 'normal', ?)"
    ).bind('patch-owner-only', getTestAgentId(), 'patch-agent-2').run();

    const res = await SELF.fetch('https://test.local/api/messages/patch-owner-only', {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${otherApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ status: 'read' }),
    });
    expect(res.status).toBe(200);
    expect((await res.json() as { status: string }).status).toBe('read');
  });

  it('updates message body', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Original body' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Updated body' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { body: string };
    expect(data.body).toBe('Updated body');
  });

  it('updates both status and body', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Original body' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'read', body: 'Updated body' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { status: string, body: string };
    expect(data.status).toBe('read');
    expect(data.body).toBe('Updated body');
  });

  it('rejects body edits for non-agent_to_boss messages', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Boss sent this', 'sent', 'normal')"
    ).bind('patch-body-forbidden', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/patch-body-forbidden', {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Should not apply' }),
    });
    expect(res.status).toBe(403);
    expect(await res.text()).toContain('only agent_to_boss messages can be edited');
  });

  it('records audit log on body edit', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'delivered', 'normal')"
    ).bind('patch-edit-audit', getTestAgentId(), 'Original').run();

    const res = await SELF.fetch('https://test.local/api/messages/patch-edit-audit', {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Edited remotely' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { body: string };
    expect(data.body).toBe('Edited remotely');
  });

  it('returns 400 when neither status nor body is provided', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'No update test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('status or body is required');
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

  it('rejects react on unsupported channel', async () => {
    // Create a message with no channel (not telegram or discord)
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
    expect(await res.text()).toContain('not supported');
  });
});
