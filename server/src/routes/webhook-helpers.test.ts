// Tests for webhook-helpers: boss lookup, routing evaluation, access checks.
// Covers asString, mapMessage, evaluateRoutingRules, resolveBossForChannel, hasBossAccess.
// Depends on cloudflare:test, test-helpers, and D1 bindings.

import { env } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, getTestAgentId } from '../test-helpers';
import { asString, mapMessage, evaluateRoutingRules, resolveBossForChannel, hasBossAccess } from './webhook-helpers';
import type { MessageRow } from '../types';

let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  // Create a boss with telegram and discord IDs
  const row = await env.DB
    .prepare("INSERT INTO bosses (name, role, telegram_user_id, discord_user_id) VALUES (?, ?, ?, ?) RETURNING id")
    .bind('Webhook Boss', 'manager', 'tg-user-999', 'dc-user-888')
    .first<{ id: string }>();
  bossId = row!.id;
  // Grant access to test agent
  await env.DB
    .prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, getTestAgentId())
    .run();
  // Create a viewer boss
  await env.DB
    .prepare("INSERT INTO bosses (name, role, telegram_user_id) VALUES (?, ?, ?)")
    .bind('Viewer Boss', 'viewer', 'tg-viewer-777')
    .run();
});

describe('asString', () => {
  it('returns string as-is', () => {
    expect(asString('hello')).toBe('hello');
  });
  it('converts number to string', () => {
    expect(asString(42)).toBe('42');
  });
  it('returns undefined for non-string/number', () => {
    expect(asString(null)).toBeUndefined();
    expect(asString(undefined)).toBeUndefined();
    expect(asString(true)).toBeUndefined();
    expect(asString({})).toBeUndefined();
  });
});

describe('mapMessage', () => {
  const base: MessageRow = {
    id: 'wh-msg-1', agent_id: 'a1', direction: 'agent_to_boss', mode: 'async',
    channel: 'telegram', body: 'test', status: 'sent', reply_to: null,
    priority: 'normal', type: 'text', target_agent_id: null, target_session_id: null,
    session_id: null, idempotency_key: null, metadata: null,
    created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
  };

  it('parses valid JSON metadata', () => {
    const result = mapMessage({ ...base, metadata: '{"key":"val"}' });
    expect(result.metadata).toEqual({ key: 'val' });
  });
  it('returns null for null metadata', () => {
    expect(mapMessage(base).metadata).toBeNull();
  });
  it('returns null for invalid JSON', () => {
    expect(mapMessage({ ...base, metadata: '{broken' }).metadata).toBeNull();
  });
});

describe('evaluateRoutingRules', () => {
  const agentId = getTestAgentId();
  const targetAgent = 'routed-agent-001';

  beforeAll(async () => {
    // Create target agent
    const { hashApiKey } = await import('../middleware/auth');
    const hash = await hashApiKey('hb_routed_key_00000000000000');
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(targetAgent, 'routed-agent', hash).run();
    // Create routing rule: messages containing "deploy" route to target agent
    await env.DB.prepare(
      "INSERT INTO routing_rules (id, owner_id, channel, pattern, target_agent_id, priority, enabled) VALUES (?, ?, 'telegram', ?, ?, 10, 1)"
    ).bind('rule-deploy', agentId, 'deploy.*prod', targetAgent).run();
  });

  it('matches routing rule by regex', async () => {
    const result = await evaluateRoutingRules(env as any, 'telegram', 'deploy to prod now', agentId);
    expect(result).toBe(targetAgent);
  });

  it('returns null when no rule matches', async () => {
    const result = await evaluateRoutingRules(env as any, 'telegram', 'hello world', agentId);
    expect(result).toBeNull();
  });

  it('returns null when matched rule targets same agent', async () => {
    // Create rule targeting self
    await env.DB.prepare(
      "INSERT INTO routing_rules (id, owner_id, channel, pattern, target_agent_id, priority, enabled) VALUES (?, ?, 'telegram', ?, ?, 5, 1)"
    ).bind('rule-self', agentId, 'self-route', agentId).run();
    const result = await evaluateRoutingRules(env as any, 'telegram', 'self-route test', agentId);
    expect(result).toBeNull();
  });

  it('skips invalid regex gracefully', async () => {
    await env.DB.prepare(
      "INSERT INTO routing_rules (id, owner_id, channel, pattern, target_agent_id, priority, enabled) VALUES (?, ?, 'telegram', ?, ?, 20, 1)"
    ).bind('rule-bad-regex', agentId, '[invalid(regex', targetAgent).run();
    // Should not throw, just skip the bad rule
    const result = await evaluateRoutingRules(env as any, 'telegram', '[invalid(regex', agentId);
    expect(result).toBeNull();
  });
});

describe('resolveBossForChannel', () => {
  it('resolves boss by telegram user ID', async () => {
    const { boss, error } = await resolveBossForChannel(env as any, 'telegram', 'tg-user-999', false);
    expect(boss).not.toBeNull();
    expect(boss!.name).toBe('Webhook Boss');
    expect(error).toBeUndefined();
  });

  it('resolves boss by discord user ID', async () => {
    const { boss } = await resolveBossForChannel(env as any, 'discord', 'dc-user-888', false);
    expect(boss).not.toBeNull();
    expect(boss!.name).toBe('Webhook Boss');
  });

  it('returns unknown sender for unrecognized user', async () => {
    const { boss, error } = await resolveBossForChannel(env as any, 'telegram', 'unknown-user', false);
    expect(boss).toBeNull();
    expect(error).toBe('unknown sender');
  });

  it('returns unknown sender when no userId', async () => {
    const { boss, error } = await resolveBossForChannel(env as any, 'telegram', undefined, false);
    expect(boss).toBeNull();
    expect(error).toBe('unknown sender');
  });

  it('blocks viewer from sending messages', async () => {
    const { boss, error } = await resolveBossForChannel(env as any, 'telegram', 'tg-viewer-777', false);
    expect(boss).toBeNull();
    expect(error).toBe('viewer cannot send messages');
  });

  it('allows viewer when allowViewer is true', async () => {
    const { boss, error } = await resolveBossForChannel(env as any, 'telegram', 'tg-viewer-777', true);
    expect(boss).not.toBeNull();
    expect(boss!.role).toBe('viewer');
    expect(error).toBeUndefined();
  });
});

describe('hasBossAccess', () => {
  it('admin has access to any agent', async () => {
    // Create admin boss
    const adminRow = await env.DB
      .prepare("INSERT INTO bosses (name, role) VALUES (?, ?) RETURNING id")
      .bind('Admin Boss', 'admin')
      .first<{ id: string }>();
    const result = await hasBossAccess(env as any, adminRow!.id, 'any-agent-id', 'admin');
    expect(result).toBe(true);
  });

  it('manager has access to granted agent', async () => {
    const result = await hasBossAccess(env as any, bossId, getTestAgentId(), 'manager');
    expect(result).toBe(true);
  });

  it('manager denied access to non-granted agent', async () => {
    const result = await hasBossAccess(env as any, bossId, 'some-other-agent', 'manager');
    expect(result).toBe(false);
  });
});
