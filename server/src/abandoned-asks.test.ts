// Abandoned asks: a day-old ask without a deadline, or any open ask of an ended session,
// expires without an answer. Covers the cron sweep, session end, and pending-input listing.
// Depends on the Worker (SELF), seeded D1, and handleScheduled.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from './test-helpers';
import { expireStaleAsks } from './abandoned-asks';

const BOSS = 'hb_abandoned_asks_boss_0001';
const hoursAgo = (hours: number): string => new Date(Date.now() - hours * 3_600_000).toISOString();
const inHours = (hours: number): string => new Date(Date.now() + hours * 3_600_000).toISOString();
const unique = (name: string): string => `aa-${name}-${crypto.randomUUID().slice(0, 8)}`;

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Abandoned Asks Boss', 'admin', BOSS, 'abandoned-asks-boss');
});

async function ask(id: string, opts: { created: string; expires?: string | null; session?: string;
  status?: string; metadata?: Record<string, unknown>; mode?: string }): Promise<void> {
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
    metadata, created_at, expires_at, session_id) VALUES (?, ?, 'agent_to_boss', ?, 'api', 'Q?', ?, ?, ?, ?, ?)`)
    .bind(id, getTestAgentId(), opts.mode ?? 'blocking', opts.status ?? 'delivered',
      JSON.stringify(opts.metadata ?? { options: ['Yes', 'No'] }), opts.created, opts.expires ?? null,
      opts.session ?? null).run();
}

async function state(id: string): Promise<{ status: string; replies: number }> {
  const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id).first<{ status: string }>();
  const replies = await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE reply_to = ?').bind(id).first<{ n: number }>();
  return { status: row?.status ?? 'missing', replies: replies?.n ?? 0 };
}

async function register(session: string): Promise<void> {
  const res = await SELF.fetch('http://localhost/api/sessions', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ id: session, project: 'abandoned-asks' }),
  });
  expect(res.status).toBe(201);
}

describe('stale sweep', () => {
  it('expires a day-old deadline-less ask without answering it and keeps the rest', async () => {
    const stale = unique('stale'); const fresh = unique('fresh'); const timed = unique('timed');
    const text = unique('text'); const replied = unique('replied');
    await ask(stale, { created: hoursAgo(30), metadata: { options: ['Yes', 'No'], default_option: 'No' } });
    await ask(fresh, { created: hoursAgo(2) });
    await ask(timed, { created: hoursAgo(30), expires: inHours(2) });
    await ask(text, { created: hoursAgo(30), metadata: {} });
    await ask(replied, { created: hoursAgo(30), status: 'replied' });
    await expireStaleAsks(env);
    expect(await state(stale)).toEqual({ status: 'expired', replies: 0 });
    expect(await state(text)).toEqual({ status: 'expired', replies: 0 });
    expect(await state(fresh)).toEqual({ status: 'delivered', replies: 0 });
    expect(await state(timed)).toEqual({ status: 'delivered', replies: 0 });
    expect(await state(replied)).toEqual({ status: 'replied', replies: 0 });
  });

  it('drops a stale ask from pending inputs before the sweep runs', async () => {
    const stale = unique('listed'); const fresh = unique('listed-fresh');
    await ask(stale, { created: hoursAgo(26) });
    await ask(fresh, { created: hoursAgo(1) });
    const res = await SELF.fetch('http://localhost/api/boss/pending-inputs', { headers: { Authorization: `Bearer ${BOSS}` } });
    expect(res.status).toBe(200);
    const ids = ((await res.json()) as { messages: { id: string }[] }).messages.map((row) => row.id);
    expect(ids).toContain(fresh);
    expect(ids).not.toContain(stale);
  });
});

describe('session end', () => {
  it('expires only the ended session\'s open asks, without choosing the default', async () => {
    const ended = unique('sess'); const live = unique('sess-live');
    await register(ended); await register(live);
    const mine = unique('mine'); const other = unique('other');
    await ask(mine, { created: hoursAgo(1), session: ended, expires: inHours(1),
      metadata: { options: ['Ship', 'Hold'], default_option: 'Hold' } });
    await ask(other, { created: hoursAgo(1), session: live });
    const res = await SELF.fetch(`http://localhost/api/sessions/${ended}`, { method: 'DELETE', headers: authHeaders() });
    expect(res.status).toBe(200);
    expect(await state(mine)).toEqual({ status: 'expired', replies: 0 });
    expect(await state(other)).toEqual({ status: 'delivered', replies: 0 });
  });

  it('expires open asks when the session reports completed, not on other statuses', async () => {
    const session = unique('sess-done');
    await register(session);
    const pending = unique('pending');
    await ask(pending, { created: hoursAgo(1), session });
    const patch = (status: string) => SELF.fetch(`http://localhost/api/sessions/${session}`, {
      method: 'PATCH', headers: authHeaders(), body: JSON.stringify({ status }),
    });
    expect((await patch('idle')).status).toBe(200);
    expect(await state(pending)).toEqual({ status: 'delivered', replies: 0 });
    expect((await patch('completed')).status).toBe(200);
    expect(await state(pending)).toEqual({ status: 'expired', replies: 0 });
  });
});
