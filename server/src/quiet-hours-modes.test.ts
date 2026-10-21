// Quiet-hours callback delivery across destination modes, channel presence, and priorities.
// Exercises the Worker send route and two scheduled drains against seeded D1.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import app from './index';
import { seedDatabase } from './test-helpers';
import { hashApiKey } from './middleware/auth';
import { handleScheduled } from './scheduled';
import type { Env } from './types';

const utcTime = (m: number): string => new Date(Date.now() + m * 60_000).toISOString().slice(11, 16);
let calls: string[] = [];

beforeAll(async () => { await seedDatabase(); });
afterEach(() => { vi.unstubAllGlobals(); });

async function setup(
  tag: string, withChannel: boolean,
): Promise<{ key: string; agent: string; cb: string }> {
  const agent = `aq-${tag}`;
  const key = `hb_aq_${tag}_key_000000001`;
  const cb = `https://cb.test/${tag}`;
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agent, agent, await hashApiKey(key)).run();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash, callback_url) VALUES (?, ?, ?, ?)')
    .bind(`${agent}-boss`, `${agent}-boss`, await hashApiKey(`${key}-b`), cb).run();
  await env.DB.prepare(
    "INSERT INTO bosses (id, name, role, agent_id, preferences) VALUES (?, ?, 'manager', ?, ?)",
  )
    .bind(`${agent}-b`, `${agent}-b`, `${agent}-boss`,
      JSON.stringify({ quiet_hours_start: utcTime(-30), quiet_hours_end: utcTime(30), timezone: 'UTC' }),
    ).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(`${agent}-b`, agent).run();
  if (withChannel) {
    await env.DB.prepare(
      "INSERT INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, 'api', '{}', 1)",
    ).bind(`cfg-${agent}`, agent).run();
  }
  return { key, agent, cb };
}

function stub(cb: string): void {
  calls = [];
  vi.stubGlobal('fetch', vi.fn(async (url: unknown, init?: RequestInit) => {
    if (String(url) === cb) calls.push((JSON.parse(String(init?.body)) as { id: string }).id);
    return new Response(null, { status: 204 });
  }));
}

async function send(key: string, mode: string, priority = 'normal'): Promise<string> {
  const ctx = createExecutionContext();
  const res = await app.fetch(new Request('https://test/api/messages', {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: `aq ${mode} ${priority}`, priority }),
  }), { ...env, DESTINATIONS_MODE: mode } as Env, ctx);
  await waitOnExecutionContext(ctx);
  expect(res.status).toBe(201);
  return (await res.json() as { id: string }).id;
}

async function drainTwice(id: string, mode: string): Promise<void> {
  await env.DB.prepare(
    "UPDATE delivery_queue SET scheduled_at = '2000-01-01T00:00:00.000Z' WHERE message_id = ?",
  ).bind(id).run();
  await handleScheduled({ ...env, DESTINATIONS_MODE: mode } as Env);
  await handleScheduled({ ...env, DESTINATIONS_MODE: mode } as Env);
}

async function queueRows(id: string) {
  return (await env.DB.prepare('SELECT channel, config, status FROM delivery_queue WHERE message_id = ?')
    .bind(id).all()).results;
}

describe('quiet-hours destination modes', () => {
  for (const mode of ['off', 'shadow', 'on']) {
    for (const withChannel of [false, true]) {
      it(`${mode} channel=${withChannel} normal: defers only in legacy modes`, async () => {
        const { key, cb } = await setup(`${mode}-${withChannel}`, withChannel);
        stub(cb);
        const id = await send(key, mode);
        const atSend = calls.length;
        const rows = await queueRows(id);
        expect(atSend).toBe(mode === 'on' ? 1 : 0);
        if (mode === 'on') expect(rows).toEqual([]);
        else expect(rows).toMatchObject([{ status: 'pending' }]);
        await drainTwice(id, mode);
        if (mode === 'on') expect(await queueRows(id)).toEqual([]);
        else expect(await queueRows(id)).toMatchObject([{ status: 'delivered' }]);
        expect(calls.filter(x => x === id).length).toBe(1);
      });
      it(`${mode} channel=${withChannel} high: immediate, never queued`, async () => {
        const { key, cb } = await setup(`${mode}-${withChannel}-hi`, withChannel);
        stub(cb);
        const id = await send(key, mode, 'high');
        expect(calls).toEqual([id]);
        expect(await queueRows(id)).toEqual([]);
        await drainTwice(id, mode);
        expect(calls).toEqual([id]);
      });
    }
  }
});
