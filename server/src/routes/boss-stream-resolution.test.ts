// Behaviour of the incremental boss feed and required-input polls on the read-budget fixture.
// Covers the feed's target branch and time-only resolution (deadline, one-day abandonment).
// Depends on cloudflare:test D1, the shared read-budget seed/meter, and the 25 ms poll interval.

import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import type { Env } from '../types';
import { seedDatabase } from '../test-helpers';
import { MeterLog, meterDatabase } from '../read-budget/meter';
import { AGENTS, STREAM_SESSION, seedHistoryLayer, seedLiveState } from '../read-budget/seed';
import { streamBossFeed } from './boss-feed-stream';
import { streamBossRequiredInputs } from './boss-required-input-stream';

type Stream = (writer: WritableStreamDefaultWriter, encoder: TextEncoder, env: Env, ids: string[]) => Promise<void>;

beforeAll(async () => {
  await seedDatabase();
  await seedLiveState();
  await seedHistoryLayer(0);
}, 120_000);

describe('incremental boss stream polls', () => {
  it('delivers a message addressed to a scoped agent through the target branch', async () => {
    const id = `rb-a2a-${Date.now()}`;
    await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
      target_agent_id, updated_at) VALUES (?, ?, 'agent_to_agent', 'async', 'api', 'peer',
      'sent', ?, datetime('now', '+5 seconds'))`).bind(id, AGENTS[3], AGENTS[15]).run();
    const events = await drive(streamBossFeed, [AGENTS[15]], (statements) => statements >= 3);
    expect(count(events, `"id":"${id}"`)).toBe(1);
  });

  it('resolves an input whose deadline passes without any row update', async () => {
    const id = `rb-deadline-${Date.now()}`;
    await insertAsk(id, new Date().toISOString(), new Date(Date.now() + 1_500).toISOString());
    await expectTimeResolution(id);
  });

  it('resolves a deadline-less input when it turns one day old', async () => {
    const id = `rb-abandoned-${Date.now()}`;
    await insertAsk(id, new Date(Date.now() - 86_400_000 + 1_500).toISOString(), null);
    await expectTimeResolution(id);
  });
});

async function expectTimeResolution(id: string): Promise<void> {
  const started = Date.now();
  const resolved = `event: resolved\ndata: {"id":"${id}"}`;
  const events = await drive(streamBossRequiredInputs, AGENTS,
    (_, text) => text.includes(resolved) || Date.now() - started > 8_000);
  expect(events.indexOf(`"id":"${id}"`)).toBeLessThan(events.indexOf('event: ready'));
  expect(events).toContain(resolved);
  expect(Date.now() - started).toBeGreaterThan(1_000);
}

async function insertAsk(id: string, createdAt: string, expiresAt: string | null): Promise<void> {
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
    session_id, metadata, created_at, expires_at) VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'Ask', 'sent',
    ?, '{"options":["Go"]}', ?, ?)`).bind(id, AGENTS[3], STREAM_SESSION, createdAt, expiresAt).run();
}

/** Runs a stream loop on a metered D1 until `stop` holds before a statement; returns the SSE text. */
async function drive(stream: Stream, agentIds: string[], stop: (statements: number, events: string) => boolean): Promise<string> {
  let events = '';
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const reader = readable.getReader();
  const reading = (async () => {
    for (let next = await reader.read(); !next.done; next = await reader.read()) {
      events += new TextDecoder().decode(next.value);
    }
  })();
  const log = new MeterLog(15);
  const metered = { ...env, DB: meterDatabase(env.DB, log, () => stop(log.statements.length, events)) } as unknown as Env;
  await stream(writable.getWriter(), new TextEncoder(), metered, agentIds);
  await reading;
  return events;
}

function count(text: string, needle: string): number {
  return text.split(needle).length - 1;
}
