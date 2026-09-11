// Message API regression suites extracted to keep each file bounded.
// Registers cases in messages.test.ts; depends on its shared database setup.
import { createAgentAuth } from './support';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId } from '../../test-helpers';
import { hashApiKey } from '../../middleware/auth';

describe('Session-scoped messages', () => {
  const agentId = getTestAgentId();
  beforeAll(async () => {
    for (const id of ['sess-aaa', 'sess-bbb', 'sess-ccc']) {
      await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(id, agentId).run();
    }
  });

  it('stores session_id on sent messages', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Session msg', session_id: 'sess-aaa' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };
    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { session_id: string | null };
    expect(msg.session_id).toBe('sess-aaa');
  });

  it('filters by session in non-unread mode', async () => {
    // Create messages in different sessions
    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'From sess-bbb', session_id: 'sess-bbb' }),
    });
    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'From sess-ccc', session_id: 'sess-ccc' }),
    });

    // Query with session filter (non-unread)
    const res = await SELF.fetch('https://test.local/api/messages?session=sess-bbb', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { body: string; session_id: string | null }[] };
    // Should include messages from sess-bbb and boss-initiated messages
    const sessB = data.messages.filter(m => m.session_id === 'sess-bbb');
    expect(sessB.length).toBeGreaterThan(0);
    // Should NOT include messages from sess-ccc
    const sessC = data.messages.filter(m => m.session_id === 'sess-ccc');
    expect(sessC.length).toBe(0);
  });

  it('scopes unread by target_session for agent-to-agent', async () => {
    // Seed: create a second agent
    const { hashApiKey } = await import('../../middleware/auth');
    const key2Hash = await hashApiKey('hb_test_key_agent2_000000');
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind('test-agent-2', 'agent-2', key2Hash).run();

    // Agent-2 sends a message targeted at agent-1's specific session
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'For session X only', 'sent', 'normal', ?, ?)"
    ).bind('a2a-sess-targeted', 'test-agent-2', agentId, 'sess-xxx').run();

    // Agent-2 sends a message targeted at agent-1 (no session)
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'For all sessions', 'sent', 'normal', ?)"
    ).bind('a2a-no-sess', 'test-agent-2', agentId).run();

    // Query unread with target_session=sess-xxx: should see both
    const res1 = await SELF.fetch('https://test.local/api/messages?unread=true&target_session=sess-xxx', {
      headers: authHeaders(),
    });
    expect(res1.status).toBe(200);
    const data1 = await res1.json() as { messages: { id: string }[] };
    const ids1 = data1.messages.map(m => m.id);
    expect(ids1).toContain('a2a-sess-targeted');
    expect(ids1).toContain('a2a-no-sess');

    // Query unread with target_session=sess-yyy: should NOT see session-targeted message
    const res2 = await SELF.fetch('https://test.local/api/messages?unread=true&target_session=sess-yyy', {
      headers: authHeaders(),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as { messages: { id: string }[] };
    const ids2 = data2.messages.map(m => m.id);
    expect(ids2).not.toContain('a2a-sess-targeted');
    expect(ids2).toContain('a2a-no-sess');
  });

  it('stores target_session_id when sending to a session', async () => {
    // Create a session for targeting
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label) VALUES (?, ?, ?)"
    ).bind('target-sess-001', agentId, 'my-session').run();

    // Send a message targeted at the session label
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Hey session', to: 'my-session' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { target_session_id: string | null; target_agent_id: string | null; direction: string };
    expect(msg.target_session_id).toBe('target-sess-001');
    expect(msg.target_agent_id).toBe(agentId);
    expect(msg.direction).toBe('agent_to_agent');
  });

  it('does not expose another agent target_session in non-unread mode', async () => {
    const { hashApiKey } = await import('../../middleware/auth');
    const key2Hash = await hashApiKey('hb_test_key_agent3_000000');
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind('test-agent-3', 'agent-3', key2Hash).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Other session target', 'sent', 'normal', ?, ?)"
    ).bind('a2a-other-session-target', 'test-agent-3', 'someone-else', 'sess-shared').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'My session target', 'sent', 'normal', ?, ?)"
    ).bind('a2a-my-session-target', 'test-agent-3', agentId, 'sess-shared').run();

    const res = await SELF.fetch('https://test.local/api/messages?target_session=sess-shared&limit=100', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { id: string }[] };
    const ids = data.messages.map(m => m.id);
    expect(ids).toContain('a2a-my-session-target');
    expect(ids).not.toContain('a2a-other-session-target');
  });

  it('excludes a session own broadcasts from its unread (self-authored a2a)', async () => {
    // A session that authored an a2a message (session_id == query session) must never
    // see it as unread, even if it was self-targeted (target_session_id == session_id).
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id, session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Self broadcast', 'sent', 'normal', ?, ?, ?)"
    ).bind('a2a-self-broadcast', agentId, agentId, 'sess-self', 'sess-self').run();
    // A genuine peer message authored by a different session, targeted at sess-self.
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id, session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Peer broadcast', 'sent', 'normal', ?, ?, ?)"
    ).bind('a2a-peer-broadcast', agentId, agentId, 'sess-self', 'sess-peer').run();

    const res = await SELF.fetch('https://test.local/api/messages?unread=true&target_session=sess-self&limit=100', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { id: string }[] };
    const ids = data.messages.map(m => m.id);
    expect(ids).not.toContain('a2a-self-broadcast');
    expect(ids).toContain('a2a-peer-broadcast');
  });

  it('does not resolve a colliding label back to the sender own session', async () => {
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now', '-1 minute'))"
    ).bind('collide-peer', agentId, 'shared-label').run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now'))"
    ).bind('collide-self', agentId, 'shared-label').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Broadcast', to: 'shared-label', session_id: 'collide-self' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { target: { id: string } };
    expect(data.target.id).toBe('collide-peer');
  });

  it('uses the newest non-self session for an exact duplicate label', async () => {
    await createAgentAuth('exact-label-peer', 'hb_test_key_exact_label_peer_000000');
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now', '-1 minute'))"
    ).bind('exact-label-old', 'exact-label-peer', 'exact-project/main').run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now'))"
    ).bind('exact-label-new', 'exact-label-peer', 'exact-project/main').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Exact duplicate label', to: 'exact-project/main' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { target: { label: string; id: string } };
    expect(data.target).toEqual({ label: 'exact-project/main', id: 'exact-label-new' });
  });
});
