// Tests for SSE streaming endpoint and its query helpers.
// Covers SQL generation, ID pruning, and integration headers.
// Depends on cloudflare:test, vitest, and stream.ts.

import { describe, it, expect, beforeAll } from 'vitest';
import { env, SELF } from 'cloudflare:test';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { buildStreamQuery, pruneSeenMessageIds } from './stream';
import { DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS, getStreamPollIntervalMs } from './stream-config';

beforeAll(async () => {
  await seedDatabase();
});

describe('stream helpers', () => {
  const agentId = 'test-agent-id';

  describe('poll interval configuration', () => {
    it('uses the documented production default when no override is present', () => {
      expect(getStreamPollIntervalMs({}, DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS))
        .toBe(DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS);
    });

    it('uses a positive integer environment override', () => {
      expect(getStreamPollIntervalMs(
        { STREAM_POLL_INTERVAL_MS: '25' },
        DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS,
      )).toBe(25);
    });

    it('falls back for invalid environment values', () => {
      expect(getStreamPollIntervalMs(
        { STREAM_POLL_INTERVAL_MS: 'not-a-duration' },
        DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS,
      )).toBe(DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS);
    });
  });

  describe('buildStreamQuery', () => {
    it('returns correct SQL for agent-only (no session)', () => {
      const { sql, buildBinds } = buildStreamQuery(agentId);
      expect(sql).toContain("messages.agent_id = ? AND messages.direction = 'boss_to_agent'");
      expect(sql).toContain("messages.target_agent_id = ? AND messages.direction = 'agent_to_agent'");
      expect(sql).not.toContain('messages.target_session_id = ?');
      
      const binds = buildBinds('2026-01-01 00:00:00');
      expect(binds).toEqual(['2026-01-01 00:00:00', agentId, agentId]);
    });

    it('returns correct SQL with session ID', () => {
      const sessionId = 'sess-123';
      const { sql, buildBinds } = buildStreamQuery(agentId, sessionId);
      expect(sql).toContain("messages.target_session_id IS NULL OR messages.target_session_id = ?");
      expect(sql).toContain('messages.target_session_id = ?');
      expect(sql).toContain('messages.target_session_id IS NULL');
      
      const binds = buildBinds('2026-01-01 00:00:00');
      expect(binds).toEqual(['2026-01-01 00:00:00', agentId, sessionId, agentId, sessionId]);
    });
  });

  describe('pruneSeenMessageIds', () => {
    it('clears set when no rows', () => {
      const seen = new Set(['m1', 'm2']);
      pruneSeenMessageIds(seen, [], '2026-01-01 00:00:00');
      expect(seen.size).toBe(0);
    });

    it('clears set when floor advances past lastCheck', () => {
      const seen = new Set(['m1']);
      const rows = [{ id: 'm2', created_at: '2026-01-01 00:00:01' } as any];
      pruneSeenMessageIds(seen, rows, '2026-01-01 00:00:00');
      expect(seen.size).toBe(0);
    });

    it('keeps set when floor <= lastCheck', () => {
      const seen = new Set(['m1']);
      const rows = [{ id: 'm2', created_at: '2026-01-01 00:00:00' } as any];
      pruneSeenMessageIds(seen, rows, '2026-01-01 00:00:00');
      expect(seen.has('m1')).toBe(true);
    });
  });
});

describe('GET /api/messages/stream', () => {
  it('returns SSE content-type headers', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/stream', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('text/event-stream');
    expect(res.headers.get('Cache-Control')).toBe('no-cache');
    // We must close the body to avoid leaking the request/hanging the test
    if (res.body) await res.body.cancel();
  });

  it('delivers pending messages as SSE events', async () => {
    const agentId = getTestAgentId();
    const msgId = `stream-test-${Date.now()}`;
    
    // Insert a pending message
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status) VALUES (?, ?, 'boss_to_agent', 'async', 'Stream this', 'sent')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch('https://test.local/api/messages/stream', {
      headers: authHeaders(),
    });
    
    expect(res.status).toBe(200);
    const reader = res.body?.getReader();
    if (!reader) throw new Error('No reader');

    // Read the first chunk
    const { value } = await reader.read();
    const text = new TextDecoder().decode(value);
    
    expect(text).toContain('event: message');
    expect(text).toContain('Stream this');
    expect(text).toContain(msgId);

    await reader.cancel();

    // Verify message status was updated to delivered
    const updated = await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(msgId).first<{ status: string }>();
    expect(updated?.status).toBe('delivered');
  });

  it('marks sent a2a messages delivered only after SSE pickup', async () => {
    const agentId = getTestAgentId();
    const msgId = `stream-a2a-${Date.now()}`;
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'A2A stream', 'sent', ?)"
    ).bind(msgId, agentId, agentId).run();

    const res = await SELF.fetch('https://test.local/api/messages/stream', {
      headers: authHeaders(),
    });
    const reader = res.body?.getReader();
    if (!reader) throw new Error('No reader');
    const { value } = await reader.read();
    expect(new TextDecoder().decode(value)).toContain(msgId);
    await reader.cancel();

    const updated = await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(msgId).first<{ status: string }>();
    expect(updated?.status).toBe('delivered');
  });
});
