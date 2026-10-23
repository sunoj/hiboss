// Every ask-closing path family fans out one resolution: boss reply API, channel callbacks,
// boss-agent inbox replies, timeout defaults, deadline expiry, session end and the stale sweep.
// Runs in relay mode (the test Worker has no APNs key) and reads the encrypted relay requests.
// Request routes defer the fan-out, so their tests wait on the execution context.
import { createExecutionContext, env, SELF, waitOnExecutionContext } from 'cloudflare:test';
import worker from '../index';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { expireSessionAsks, expireStaleAsks } from '../abandoned-asks';
import { persistOptionReply } from '../routes/boss-option-reply';
import { handleScheduled } from '../scheduled';
import { seedBossToken, seedDatabase } from '../test-helpers';
import type { MessageRow } from '../types';
import { captureFetch, insertAsk, relayResolutions, seedAudience } from './resolution-test-support';

const BOSS_TOKEN = `hb_boss_resolution_paths_${'ab'.repeat(8)}`;
const BOSS_AGENT_KEY = 'hb_resolution_boss_agent_key_000000';
let agentId: string;

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Paths boss', 'manager', BOSS_TOKEN, 'paths-boss');
  ({ agentId } = await seedAudience('paths', { token: '', relay: true }));
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('paths-boss-agent', 'paths boss agent', await hashApiKey(BOSS_AGENT_KEY)).run();
  await env.DB.prepare(`INSERT INTO bosses (id, name, role, agent_id) VALUES ('paths-agent-boss', 'Agent boss', 'manager', 'paths-boss-agent')`).run();
  await env.DB.prepare(`INSERT INTO boss_agent_access (boss_id, agent_id) VALUES ('paths-agent-boss', ?)`).bind(agentId).run();
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function watch(id: string, close: () => Promise<unknown>): Promise<unknown[]> {
  const captured = captureFetch(202);
  await close();
  return (await relayResolutions(captured)).filter((r) => r.id === id).map((r) => r.status);
}

async function post(path: string, token: string, body: unknown, ctx: ExecutionContext): Promise<Response> {
  return worker.fetch(new Request(`https://test${path}`, { method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body) }), env, ctx);
}

/** Posts a reply, expects 201, then lets the deferred fan-out finish. */
async function reply(path: string, token: string, body: unknown): Promise<void> {
  const ctx = createExecutionContext();
  expect((await post(path, token, body, ctx)).status).toBe(201);
  await waitOnExecutionContext(ctx);
}

const row = (id: string) => env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();

describe('resolution fan-out per closing path', () => {
  it('boss reply API (iOS, Mac, web)', async () => {
    await insertAsk('paths-boss-reply', agentId);
    expect(await watch('paths-boss-reply', () => reply('/api/boss/messages/paths-boss-reply/reply', BOSS_TOKEN,
      { body: 'Ship' }))).toEqual(['replied']);
  });

  it('answers the boss reply without waiting for a hanging push', async () => {
    await insertAsk('paths-hang', agentId);
    let release = () => {};
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const relay = vi.fn(async () => { await gate; return new Response('{}', { status: 202 }); });
    vi.stubGlobal('fetch', relay);
    const ctx = createExecutionContext();
    const late = new Promise<'late'>((resolve) => setTimeout(() => resolve('late'), 1_000));
    const response = await Promise.race([post('/api/boss/messages/paths-hang/reply', BOSS_TOKEN,
      { body: 'Ship' }, ctx), late]);
    release();
    await waitOnExecutionContext(ctx);
    expect(response === 'late' ? 'late' : response.status).toBe(201);
    expect(relay).toHaveBeenCalled();
  });

  it('channel option callback (the shared Telegram/Discord claim)', async () => {
    await insertAsk('paths-callback', agentId, { channel: 'telegram' });
    const parent = (await row('paths-callback'))!;
    expect(await watch('paths-callback', () => persistOptionReply(env, parent, 'Hold', false,
      'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, reply_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
      ['paths-callback-answer', agentId, 'boss_to_agent', 'async', 'telegram', 'Hold', 'sent', 'normal', parent.id], null,
    ))).toEqual(['replied']);
  });

  it('boss-agent inbox reply (agent credential)', async () => {
    await insertAsk('paths-inbox', agentId, { mode: 'blocking', metadata: null });
    expect(await watch('paths-inbox', () => reply('/api/boss/inbox/paths-inbox/reply', BOSS_AGENT_KEY,
      { body: 'Go' }))).toEqual(['replied']);
  });

  it('deadline sweep: timeout default and expiry without a default', async () => {
    const past = new Date(Date.now() - 60_000).toISOString();
    await insertAsk('paths-default', agentId, { expires_at: past,
      metadata: JSON.stringify({ options: ['Ship', 'Hold'], default_option: 'Hold' }) });
    await insertAsk('paths-deadline', agentId, { expires_at: past });
    const captured = captureFetch(202);
    await handleScheduled(env);
    const statuses = Object.fromEntries((await relayResolutions(captured))
      .filter((r) => String(r.id).startsWith('paths-')).map((r) => [r.id, r.status]));
    expect(statuses).toEqual({ 'paths-default': 'replied', 'paths-deadline': 'expired' });
  });

  it('session end expires each open ask once', async () => {
    await env.DB.prepare("INSERT INTO sessions (id, agent_id, label, status) VALUES ('paths-session', ?, 'paths', 'working')")
      .bind(agentId).run();
    await insertAsk('paths-session-a', agentId, { session_id: 'paths-session' });
    await insertAsk('paths-session-b', agentId, { session_id: 'paths-session', mode: 'blocking', metadata: null });
    const captured = captureFetch(202);
    await expireSessionAsks(env, agentId, 'paths-session');
    const ids = (await relayResolutions(captured)).map((r) => `${r.id}:${r.status}`).sort();
    expect(ids).toEqual(['paths-session-a:expired', 'paths-session-b:expired']);
  });

  it('stale sweep', async () => {
    await insertAsk('paths-stale', agentId, { created_at: '2020-01-01 00:00:00' });
    expect(await watch('paths-stale', () => expireStaleAsks(env))).toEqual(['expired']);
  });

  it('does not fan out when the ask was already closed', async () => {
    await insertAsk('paths-closed', agentId, { status: 'replied' });
    expect(await watch('paths-closed', () => SELF.fetch('https://test/api/boss/messages/paths-closed/reply', {
      method: 'POST', headers: { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'Late' }) }))).toEqual([]);
  });
});
