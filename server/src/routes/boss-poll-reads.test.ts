// Rows-read budgets for the boss feed and required-input SSE polls on a production-sized table.
// Meters D1 meta.rows_read per statement and checks time-only resolution of pending inputs.
// Depends on cloudflare:test D1, the stream loops, and the injected 25 ms poll interval.

import { env } from 'cloudflare:test';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Env } from '../types';
import { seedDatabase } from '../test-helpers';
import { streamBossFeed } from './boss-feed-stream';
import { streamBossRequiredInputs } from './boss-required-input-stream';

// Production shape: ~32 k messages, two agents with ~10 k each, a long tail, a handful pending.
const VOLUMES = [10_000, 9_000, 4_000, 3_000, 2_000, 1_500, 1_000, 600, 400, 200, 150, 80, 40, 20, 8, 2];
const AGENTS = VOLUMES.map((_, index) => `poll-agent-${String(index).padStart(2, '0')}`);
const IDLE_POLL_BUDGET = 100;

interface Read { sql: string; binds: unknown[]; rows: number }
type Stream = (writer: WritableStreamDefaultWriter, encoder: TextEncoder, env: Env, ids: string[]) => Promise<void>;

beforeAll(async () => {
  await seedDatabase();
  await env.DB.batch(AGENTS.concat('poll-outside').map((id) => env.DB
    .prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)').bind(id, id, `hash-${id}`)));
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x + 1 FROM n WHERE x < 199)
    INSERT INTO sessions (id, agent_id, label) SELECT 'poll-session-' || x, ?, 'poll/' || x FROM n`)
    .bind(AGENTS[0]).run();
  let offset = 0;
  for (const [index, volume] of VOLUMES.entries()) {
    await seedHistory(AGENTS[index], AGENTS[(index + 1) % AGENTS.length], offset, volume);
    offset += volume;
  }
  for (let index = 0; index < 6; index += 1) {
    await insertAsk(`poll-pending-${index}`, AGENTS[index * 2], new Date(Date.now() - 3_600_000).toISOString(),
      index < 2 ? new Date(Date.now() + 7_200_000).toISOString() : null, index % 2 === 0);
  }
}, 60_000);

afterAll(async () => {
  await env.DB.prepare("DELETE FROM messages WHERE id LIKE 'poll-%'").run();
  await env.DB.prepare("DELETE FROM sessions WHERE id LIKE 'poll-%'").run();
  await env.DB.prepare("DELETE FROM api_keys WHERE id LIKE 'poll-%'").run();
});

describe('boss stream polls on a 32 k-message table', () => {
  it('reads at most the idle budget per feed poll', async () => {
    const { reads } = await drive(streamBossFeed, AGENTS, (log) => log.length >= 10);
    await report('feed', reads);
    expect(reads).toHaveLength(10);
    for (const read of reads) expect(read.rows).toBeLessThanOrEqual(IDLE_POLL_BUDGET);
  });

  it('reads at most the idle budget per required-input poll after the first full scan', async () => {
    const { reads, events } = await drive(streamBossRequiredInputs, AGENTS, (log) => log.length >= 11);
    await report('required-inputs', reads);
    // The first scan proves the meter counts visited rows, not returned rows.
    expect(reads[0].rows).toBeGreaterThan(1_000);
    for (const read of reads.slice(1)) expect(read.rows).toBeLessThanOrEqual(IDLE_POLL_BUDGET);
    expect(count(events, 'event: message')).toBe(6);
    expect(count(events, 'event: ready')).toBe(1);
    expect(events).not.toContain('event: resolved');
  });

  it('delivers a message addressed to a scoped agent through the target branch', async () => {
    const id = `poll-a2a-${Date.now()}`;
    await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
      target_agent_id, updated_at) VALUES (?, 'poll-outside', 'agent_to_agent', 'async', 'api', 'peer',
      'sent', ?, datetime('now', '+5 seconds'))`).bind(id, AGENTS[15]).run();
    const { events } = await drive(streamBossFeed, [AGENTS[15]], (log) => log.length >= 3);
    expect(count(events, `"id":"${id}"`)).toBe(1);
  });

  it('resolves an input whose deadline passes without any row update', async () => {
    const id = `poll-deadline-${Date.now()}`;
    await insertAsk(id, AGENTS[3], new Date().toISOString(), new Date(Date.now() + 1_500).toISOString(), true);
    await expectTimeResolution(id);
  });

  it('resolves a deadline-less input when it turns one day old', async () => {
    const id = `poll-abandoned-${Date.now()}`;
    await insertAsk(id, AGENTS[4], new Date(Date.now() - 86_400_000 + 1_500).toISOString(), null, false);
    await expectTimeResolution(id);
  });
});

async function expectTimeResolution(id: string): Promise<void> {
  const started = Date.now();
  const resolved = `event: resolved\ndata: {"id":"${id}"}`;
  const { reads, events } = await drive(streamBossRequiredInputs, AGENTS,
    (_, text) => text.includes(resolved) || Date.now() - started > 8_000);
  expect(events.indexOf(`"id":"${id}"`)).toBeLessThan(events.indexOf('event: ready'));
  expect(events).toContain(resolved);
  expect(Date.now() - started).toBeGreaterThan(1_000);
  for (const read of reads.slice(1)) expect(read.rows).toBeLessThanOrEqual(IDLE_POLL_BUDGET);
}

async function seedHistory(agent: string, peer: string, offset: number, volume: number): Promise<void> {
  // One in ten is an answered decision, two in ten are peer messages to the next agent.
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(?) UNION ALL SELECT x + 1 FROM n WHERE x < ?)
    INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, target_agent_id,
      session_id, metadata, created_at, updated_at)
    SELECT 'poll-m-' || x, ?,
      CASE WHEN x % 10 < 5 THEN 'agent_to_boss' WHEN x % 10 < 8 THEN 'boss_to_agent' ELSE 'agent_to_agent' END,
      CASE WHEN x % 30 = 1 THEN 'blocking' ELSE 'async' END, 'api', 'history ' || x,
      CASE WHEN x % 10 < 2 THEN 'replied' ELSE 'read' END,
      CASE WHEN x % 10 >= 8 THEN ? END, 'poll-session-' || (x % 200),
      CASE WHEN x % 10 = 0 THEN '{"options":["Yes","No"]}' END,
      datetime('2026-01-01', '+' || (x * 800) || ' seconds'),
      datetime('2026-01-01', '+' || (x * 800) || ' seconds') FROM n`)
    .bind(offset, offset + volume - 1, agent, peer).run();
}

async function insertAsk(
  id: string, agent: string, createdAt: string, expiresAt: string | null, options: boolean,
): Promise<void> {
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
    session_id, metadata, created_at, expires_at) VALUES (?, ?, 'agent_to_boss', ?, 'api', 'Ask', 'sent',
    'poll-session-1', ?, ?, ?)`)
    .bind(id, agent, options ? 'async' : 'blocking', options ? '{"options":["Go"]}' : null, createdAt, expiresAt)
    .run();
}

/** Runs a stream loop on a metered D1 until `stop` holds before a statement; returns reads and SSE text. */
async function drive(
  stream: Stream, agentIds: string[], stop: (reads: Read[], events: string) => boolean,
): Promise<{ reads: Read[]; events: string }> {
  const reads: Read[] = [];
  let events = '';
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const reader = readable.getReader();
  const reading = (async () => {
    for (let next = await reader.read(); !next.done; next = await reader.read()) {
      events += new TextDecoder().decode(next.value);
    }
  })();
  const metered = { ...env, DB: meter(env.DB, reads, () => stop(reads, events)) } as unknown as Env;
  await stream(writable.getWriter(), new TextEncoder(), metered, agentIds);
  await reading;
  return { reads, events };
}

function meter(db: D1Database, reads: Read[], stop: () => boolean): D1Database {
  const wrap = (sql: string, statement: D1PreparedStatement, binds: unknown[] = []): D1PreparedStatement => ({
    bind: (...values: unknown[]) => wrap(sql, statement.bind(...values), values),
    all: async <T>() => {
      if (stop()) throw new Error('poll budget reached');
      const result = await statement.all<T>();
      reads.push({ sql, binds, rows: result.meta.rows_read });
      return result;
    },
  }) as unknown as D1PreparedStatement;
  return { prepare: (sql: string) => wrap(sql, db.prepare(sql)) } as unknown as D1Database;
}

async function report(name: string, reads: Read[]): Promise<void> {
  const last = reads.at(-1);
  const plan = last ? await env.DB.prepare(`EXPLAIN QUERY PLAN ${last.sql}`).bind(...last.binds)
    .all<{ detail: string }>() : null;
  console.info(`POLL_READS ${JSON.stringify({ name, rows_read: reads.map((read) => read.rows),
    idle_plan: plan?.results.map((row) => row.detail) })}`);
}

function count(text: string, needle: string): number {
  return text.split(needle).length - 1;
}
