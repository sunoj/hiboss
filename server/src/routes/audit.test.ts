// Integration tests for audit logging across mutations.
// Verifies that logAudit writes entries and GET /api/audit queries them.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { logAudit } from '../audit';

beforeAll(async () => {
  await seedDatabase();
});

describe('logAudit', () => {
  it('writes an audit entry to D1', async () => {
    await logAudit(env as never, 'agent', 'test-agent-id', 'test.action', 'test_resource', 'res-1', 'test details');
    const row = await env.DB
      .prepare("SELECT * FROM audit_log WHERE action = 'test.action' LIMIT 1")
      .first<{ actor_type: string; actor_id: string; action: string; resource_type: string; resource_id: string; details: string }>();
    expect(row).not.toBeNull();
    expect(row!.actor_type).toBe('agent');
    expect(row!.actor_id).toBe('test-agent-id');
    expect(row!.resource_type).toBe('test_resource');
    expect(row!.resource_id).toBe('res-1');
    expect(row!.details).toBe('test details');
  });

  it('handles null optional fields', async () => {
    await logAudit(env as never, 'system', 'sys', 'test.minimal');
    const row = await env.DB
      .prepare("SELECT * FROM audit_log WHERE action = 'test.minimal' LIMIT 1")
      .first<{ resource_type: string | null; resource_id: string | null; details: string | null }>();
    expect(row).not.toBeNull();
    expect(row!.resource_type).toBeNull();
    expect(row!.resource_id).toBeNull();
    expect(row!.details).toBeNull();
  });
});

describe('GET /api/audit', () => {
  beforeAll(async () => {
    // Seed some audit entries
    await logAudit(env as never, 'agent', getTestAgentId(), 'message.send', 'message', 'msg-audit-1');
    await logAudit(env as never, 'boss', 'boss-1', 'message.reply', 'message', 'msg-audit-2');
    await logAudit(env as never, 'agent', getTestAgentId(), 'channel.set', 'channel_config', 'cc-1', 'telegram');
  });

  it('returns audit entries', async () => {
    const res = await SELF.fetch('https://test.local/api/audit', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { entries: unknown[]; total: number };
    expect(data.entries.length).toBeGreaterThan(0);
    expect(data.total).toBeGreaterThan(0);
  });

  it('filters by actor_type', async () => {
    const res = await SELF.fetch('https://test.local/api/audit?actor_type=boss', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { entries: { actor_type: string }[] };
    for (const entry of data.entries) {
      expect(entry.actor_type).toBe('boss');
    }
  });

  it('filters by action', async () => {
    const res = await SELF.fetch('https://test.local/api/audit?action=message.send', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { entries: { action: string }[] };
    for (const entry of data.entries) {
      expect(entry.action).toBe('message.send');
    }
  });

  it('supports limit and offset', async () => {
    const res = await SELF.fetch('https://test.local/api/audit?limit=1&offset=0', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { entries: unknown[] };
    expect(data.entries.length).toBeLessThanOrEqual(1);
  });
});

describe('Audit from message send', () => {
  it('creates audit entry when sending a message', async () => {
    // Clear existing audit entries for message.send to isolate this test
    const before = await env.DB
      .prepare("SELECT COUNT(*) AS c FROM audit_log WHERE action = 'message.send' AND actor_id = ?")
      .bind(getTestAgentId())
      .first<{ c: number }>();
    const countBefore = before?.c ?? 0;

    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Audit test message' }),
    });

    // Wait a tick for waitUntil to complete
    await new Promise((r) => setTimeout(r, 50));

    const after = await env.DB
      .prepare("SELECT COUNT(*) AS c FROM audit_log WHERE action = 'message.send' AND actor_id = ?")
      .bind(getTestAgentId())
      .first<{ c: number }>();
    expect((after?.c ?? 0)).toBeGreaterThan(countBefore);
  });
});
