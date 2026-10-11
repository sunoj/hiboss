// Ask lifetime regressions through authenticated routes and the D1 expiry sweep.
// Covers older CLI payloads, poll windows, later boss replies, and default provenance.
// Dependencies: messagesRouter, Cloudflare test contexts, and seeded D1 fixtures.

import { createExecutionContext, env, SELF, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { handleScheduled } from '../scheduled';
import type { MessageResponse, MessageRow } from '../types';
import { messagesRouter } from './messages';

const bossToken = 'synthetic-ask-timeout-boss';

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('Ask timeout boss', 'manager', bossToken);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(boss, getTestAgentId()).run();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

async function request(path: string, payload?: Record<string, unknown>): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await messagesRouter.fetch(new Request(`https://test.local${path}`, {
    method: 'POST', headers: authHeaders(), body: payload ? JSON.stringify(payload) : undefined,
  }), env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

async function send(payload: Record<string, unknown> = {}): Promise<MessageRow> {
  const response = await request('/', {
    body: 'Choose a path', mode: 'blocking', options: ['A', 'B'], ...payload,
  });
  expect(response.status).toBe(201);
  const { id } = await response.json() as { id: string };
  const row = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!row) throw new Error('sent ask missing');
  return row;
}

async function endPollWindow(id: string): Promise<MessageResponse> {
  const now = Date.now();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(now + 300_001);
  // Advance only the poll clock; real D1 and waitUntil work still complete normally.
  const clock = vi.spyOn(Date, 'now').mockReturnValueOnce(now).mockReturnValue(now + 300_001);
  try {
    const response = await request(`/${id}/poll?timeout=300`);
    expect(response.status).toBe(200);
    return await response.json() as MessageResponse;
  } finally {
    clock.mockRestore();
  }
}

describe('legacy ask lifetime', () => {
  it.each([false, true])('preserves the old CLI one-poll 300s lifetime, default=%s', async (hasDefault) => {
    const ask = await send(hasDefault ? { metadata: { default_option: 'A' } } : {});
    const poll = await endPollWindow(ask.id);
    expect(poll.replies).toEqual([]);
    const stored = await env.DB.prepare('SELECT * FROM messages WHERE id = ?')
      .bind(ask.id).first<MessageRow>();
    expect(stored?.status).toBe(hasDefault ? 'replied' : 'expired');
    expect(JSON.parse(stored?.metadata ?? '{}').options_expired).toBe(true);
    const answers = await env.DB.prepare('SELECT * FROM messages WHERE reply_to = ?')
      .bind(ask.id).all<MessageRow>();
    expect(answers.results).toHaveLength(hasDefault ? 1 : 0);
    if (hasDefault) {
      expect(answers.results[0].body).toBe('A');
      expect(JSON.parse(answers.results[0].metadata ?? '{}').auto_default).toBe(true);
    }
    expect(Date.parse(ask.expires_at ?? '') - Date.parse(ask.created_at + 'Z'))
      .toBeGreaterThanOrEqual(300_000);
    expect(Date.parse(ask.expires_at ?? '') - Date.parse(ask.created_at + 'Z'))
      .toBeLessThan(301_000);
  });
});

describe('explicit ask lifetime', () => {
  it('returns a later-window boss reply for a caller with an explicit lifetime', async () => {
    const ask = await send({ timeout: 1800 });
    const poll = await endPollWindow(ask.id);
    expect(poll.replies).toEqual([]);
    const open = await env.DB.prepare('SELECT * FROM messages WHERE id = ?')
      .bind(ask.id).first<MessageRow>();
    expect(open?.status).toBe('sent');
    expect(JSON.parse(open?.metadata ?? '{}').options_expired).not.toBe(true);
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(Date.parse(ask.expires_at ?? '') - 1000));
    const reply = await SELF.fetch(`https://test.local/api/boss/messages/${ask.id}/reply`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${bossToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'B' }),
    });
    expect(reply.status).toBe(201);
    const response = await request(`/${ask.id}/poll?timeout=300`);
    const result = await response.json() as MessageResponse;
    expect(result.replies?.[0].body).toBe('B');
    expect(result.replies?.[0].metadata?.auto_default).not.toBe(true);
  });
});

describe('ask expiry range', () => {
  it.each([
    ['blocking', undefined, 300], ['blocking', 1, 60], ['blocking', 86400, 86400],
    ['blocking', 90000, 86400], ['async', undefined, 300], ['async', 86400, 300],
  ])('sets %s expiry for timeout %s to %s seconds', async (mode, timeout, expected) => {
    const before = Date.now();
    const ask = await send({ mode, ...(timeout === undefined ? {} : { timeout }) });
    const expiry = Date.parse(ask.expires_at ?? '');
    expect(expiry).toBeGreaterThanOrEqual(before + Number(expected) * 1000);
    expect(expiry).toBeLessThanOrEqual(Date.now() + Number(expected) * 1000);
  });
});

describe('ask default deadline', () => {
  it('applies the automatic default only when the expiry sweep reaches expires_at', async () => {
    const ask = await send({ timeout: 86400, metadata: { default_option: 'A' } });
    await endPollWindow(ask.id);
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(Date.now() + 301_000));
    await handleScheduled(env);
    const open = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(ask.id).first<{ status: string }>();
    expect(open?.status).toBe('sent');
    vi.setSystemTime(new Date(Date.parse(ask.expires_at ?? '') + 1));
    await handleScheduled(env);
    const response = await request(`/${ask.id}/poll?timeout=300`);
    const result = await response.json() as MessageResponse;
    expect(result.replies?.[0].body).toBe('A');
    expect(result.replies?.[0].metadata?.auto_default).toBe(true);
  });
});
