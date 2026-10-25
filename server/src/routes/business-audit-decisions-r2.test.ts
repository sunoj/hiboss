// Round-two decision regressions: who may answer an ask and how timeouts close it.
// Covers decision-only reconcile reads, boss-agent self-answers, a2a timeouts and superseded asks.
// Depends on SELF, seeded D1 fixtures, the scheduled sweep and option expiry helpers.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { createAgent } from '../agent-keys';
import { handleScheduled } from '../scheduled';
import { seedBossToken, seedDatabase } from '../test-helpers';
import type { Env, MessageRow } from '../types';
import { expirePreviousOptions } from './message-options';

const api = 'https://test.local/api';
const unique = (name: string): string => `d2-${name}-${crypto.randomUUID().slice(0, 8)}`;
const headers = (key: string): Record<string, string> => ({ Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' });
const minutes = (offset: number): string => new Date(Date.now() + offset * 60_000).toISOString();

async function agent(name: string): Promise<{ id: string; key: string }> {
  const created = await createAgent(env.DB, unique(name), { type: 'system', id: 'decisions-r2-test' });
  if (!created) throw new Error('agent fixture missing');
  return created;
}

interface AskFixture {
  agentId: string; direction?: 'agent_to_boss' | 'agent_to_agent'; target?: string | null;
  metadata?: Record<string, unknown>; expiresAt?: string; sessionId?: string | null; createdAt?: string;
  targetSession?: string | null;
}

async function ask(fixture: AskFixture): Promise<string> {
  const id = unique('ask');
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata, expires_at, target_agent_id, session_id, created_at,
     target_session_id)
    VALUES (?, ?, ?, 'blocking', 'api', 'Deploy prod?', 'sent', ?, ?, ?, ?, COALESCE(?, datetime('now')), ?)`)
    .bind(id, fixture.agentId, fixture.direction ?? 'agent_to_boss',
      JSON.stringify(fixture.metadata ?? { options: ['Yes', 'No'] }), fixture.expiresAt ?? minutes(30),
      fixture.target ?? null, fixture.sessionId ?? null, fixture.createdAt ?? null, fixture.targetSession ?? null).run();
  return id;
}

async function row(id: string): Promise<MessageRow> {
  const found = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!found) throw new Error(`message ${id} missing`);
  return found;
}

async function answers(id: string): Promise<number> {
  const found = await env.DB.prepare("SELECT COUNT(*) AS total FROM messages WHERE reply_to = ? AND direction = 'boss_to_agent'")
    .bind(id).first<{ total: number }>();
  return found?.total ?? 0;
}

beforeAll(async () => { await seedDatabase(); });

describe('MA1 the reconcile read returns only decision replies', () => {
  it('omits the asking agent\'s own reply from the decision view', async () => {
    const asker = await agent('ma1');
    const id = await ask({ agentId: asker.id });
    const own = await SELF.fetch(`${api}/messages/${id}/reply`, {
      method: 'POST', headers: headers(asker.key), body: JSON.stringify({ body: 'Yes' }),
    });
    expect(own.status).toBe(201);
    // CONTROL: the plain thread read still shows the agent's own follow-up.
    const thread = await (await SELF.fetch(`${api}/messages/${id}`, { headers: headers(asker.key) }))
      .json() as { replies: { direction: string }[] };
    expect(thread.replies.map(reply => reply.direction)).toEqual(['agent_to_boss']);
    const decisions = await (await SELF.fetch(`${api}/messages/${id}?replies=decisions`, { headers: headers(asker.key) }))
      .json() as { replies: unknown[]; status: string };
    expect({ replies: decisions.replies, status: decisions.status }).toEqual({ replies: [], status: 'sent' });
  });

  it('omits the asker\'s own follow-up on an agent-to-agent ask but keeps the peer answer', async () => {
    const asker = await agent('ma1-a');
    const peer = await agent('ma1-b');
    const id = await ask({ agentId: asker.id, direction: 'agent_to_agent', target: peer.id });
    const statuses: string[] = [];
    for (const [key, body] of [[asker.key, 'self'], [peer.key, 'peer']] as const) {
      const response = await SELF.fetch(`${api}/messages/${id}/reply`, {
        method: 'POST', headers: headers(key), body: JSON.stringify({ body }),
      });
      expect(response.status).toBe(201);
      statuses.push((await row(id)).status);
    }
    // A non-answer leaves the ask open; only the peer's answer closes it.
    expect(statuses).toEqual(['sent', 'replied']);
    const decisions = await (await SELF.fetch(`${api}/messages/${id}?replies=decisions`, { headers: headers(asker.key) }))
      .json() as { replies: { body: string }[] };
    expect(decisions.replies.map(reply => reply.body)).toEqual(['peer']);
  });
});

describe('MA5 a boss-agent cannot answer its own ask through the inbox', () => {
  it('rejects the self-answer and keeps the ask open', async () => {
    const bossAgent = await agent('ma5-boss');
    const sub = await agent('ma5-sub');
    await env.DB.prepare("INSERT INTO bosses (id, name, role, agent_id) VALUES (?, ?, 'admin', ?)")
      .bind(unique('boss'), unique('boss-name'), bossAgent.id).run();
    // CONTROL: the boss-agent answers a sub-agent's ask.
    const subAsk = await ask({ agentId: sub.id });
    const control = await SELF.fetch(`${api}/boss/inbox/${subAsk}/reply`, {
      method: 'POST', headers: headers(bossAgent.key), body: JSON.stringify({ body: 'Yes' }),
    });
    expect(control.status).toBe(201);
    const ownAsk = await ask({ agentId: bossAgent.id });
    const response = await SELF.fetch(`${api}/boss/inbox/${ownAsk}/reply`, {
      method: 'POST', headers: headers(bossAgent.key), body: JSON.stringify({ body: 'Yes' }),
    });
    expect({ status: response.status, answers: await answers(ownAsk), parent: (await row(ownAsk)).status })
      .toEqual({ status: 403, answers: 0, parent: 'sent' });
  });
});

describe('MA3 a timed-out agent-to-agent ask closes once without a boss default', () => {
  it('expires the peer ask on the first sweep and writes no boss_to_agent row', async () => {
    const asker = await agent('ma3-a');
    const peer = await agent('ma3-b');
    // CONTROL: a boss ask with a default is answered once by the sweep.
    const bossAsk = await ask({ agentId: asker.id, expiresAt: minutes(-1), metadata: { options: ['Yes', 'No'], default_option: 'Yes' } });
    const id = await ask({ agentId: asker.id, direction: 'agent_to_agent', target: peer.id, expiresAt: minutes(-1),
      metadata: { options: ['Yes', 'No'], default_option: 'Yes' } });
    await handleScheduled(env as Env);
    await handleScheduled(env as Env);
    expect({ answers: await answers(bossAsk), status: (await row(bossAsk)).status }).toEqual({ answers: 1, status: 'replied' });
    expect({ answers: await answers(id), status: (await row(id)).status }).toEqual({ answers: 0, status: 'expired' });
  });

  it('selects the earliest deadlines first so earlier unclosed rows cannot starve a due ask', async () => {
    // Agent ids order the (agent_id, expires_at) index: the filler sorts before the due ask's agent.
    const filler = `aaaa${crypto.randomUUID().replaceAll('-', '')}`;
    const late = `zzzz${crypto.randomUUID().replaceAll('-', '')}`;
    for (const id of [filler, late]) {
      await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)').bind(id, id, id).run();
    }
    const peer = await agent('ma3-peer');
    for (let index = 0; index < 50; index += 1) {
      await ask({ agentId: filler, direction: 'agent_to_agent', target: peer.id, expiresAt: '2001-01-01T00:00:00.000Z',
        metadata: { options: ['Yes', 'No'], default_option: 'Yes' } });
    }
    const due = await ask({ agentId: late, expiresAt: '2000-01-01T00:00:00.000Z' });
    await handleScheduled(env as Env);
    expect((await row(due)).status).toBe('expired');
  });
});

describe('MA6 a superseded ask expires without its default', () => {
  it('expires the older ask and records no answer', async () => {
    const asker = await agent('ma6');
    const sessionId = unique('session');
    await env.DB.prepare('INSERT INTO sessions (id, agent_id, label) VALUES (?, ?, ?)').bind(sessionId, asker.id, sessionId).run();
    const older = await ask({ agentId: asker.id, sessionId, createdAt: '2026-01-01 00:00:00',
      metadata: { options: ['Approve', 'Reject'], default_option: 'Approve' } });
    // CONTROL: an ask in another session is not superseded.
    const otherSession = await ask({ agentId: asker.id, createdAt: '2026-01-01 00:00:00',
      metadata: { options: ['Approve', 'Reject'], default_option: 'Approve' } });
    const newer = await ask({ agentId: asker.id, sessionId, createdAt: '2026-01-01 00:00:05' });
    await expirePreviousOptions(env as Env, asker.id, sessionId, newer);
    expect((await row(otherSession)).status).toBe('sent');
    expect({ status: (await row(older)).status, answers: await answers(older) }).toEqual({ status: 'expired', answers: 0 });
  });
});

describe('only a decision reply closes an agent-to-agent ask', () => {
  it('refuses a boss inbox reply to an agent-to-agent parent', async () => {
    const bossAgent = await agent('close-boss');
    const sub = await agent('close-sub');
    const peer = await agent('close-peer');
    await env.DB.prepare("INSERT INTO bosses (id, name, role, agent_id) VALUES (?, ?, 'admin', ?)")
      .bind(unique('boss'), unique('boss-name'), bossAgent.id).run();
    const id = await ask({ agentId: sub.id, direction: 'agent_to_agent', target: peer.id });
    const response = await SELF.fetch(`${api}/boss/inbox/${id}/reply`, {
      method: 'POST', headers: headers(bossAgent.key), body: JSON.stringify({ body: 'Yes' }),
    });
    expect({ status: response.status, parent: (await row(id)).status }).toEqual({ status: 404, parent: 'sent' });
  });

  it('keeps an agent-to-agent ask open after a boss API reply', async () => {
    const sub = await agent('close-api-sub');
    const peer = await agent('close-api-peer');
    const token = `hb_${unique('boss-token')}`;
    await seedBossToken(unique('close-api-boss'), 'admin', token);
    const id = await ask({ agentId: sub.id, direction: 'agent_to_agent', target: peer.id });
    const response = await SELF.fetch(`${api}/boss/messages/${id}/reply`, {
      method: 'POST', headers: headers(token), body: JSON.stringify({ body: 'Yes' }),
    });
    expect(response.status).toBe(201);
    // The route closes a parent in waitUntil; give that write time to land before reading.
    await new Promise(resolve => setTimeout(resolve, 100));
    expect((await row(id)).status).toBe('sent');
  });
});

describe('an ask to another session of the same agent', () => {
  it('counts a reply from the addressed session and refuses a session the replier does not own', async () => {
    const asker = await agent('same-agent');
    const other = await agent('same-other');
    const [first, second, foreign] = [unique('s1'), unique('s2'), unique('sx')];
    for (const [id, owner] of [[first, asker.id], [second, asker.id], [foreign, other.id]] as const) {
      await env.DB.prepare('INSERT INTO sessions (id, agent_id, label) VALUES (?, ?, ?)').bind(id, owner, id).run();
    }
    const id = await ask({ agentId: asker.id, direction: 'agent_to_agent', target: asker.id, sessionId: first, targetSession: second });
    const reply = (body: Record<string, unknown>) => SELF.fetch(`${api}/messages/${id}/reply`, {
      method: 'POST', headers: headers(asker.key), body: JSON.stringify(body),
    });
    expect((await reply({ body: 'Yes', session_id: foreign })).status).toBe(400);
    // CONTROL: a reply that names no session cannot be told apart from the asker, so it stays a non-answer.
    expect((await reply({ body: 'Maybe' })).status).toBe(201);
    expect((await row(id)).status).toBe('sent');
    const answered = await reply({ body: 'Yes', session_id: second });
    expect(answered.status).toBe(201);
    const stored = await answered.json() as MessageRow;
    const events = await env.DB.prepare('SELECT session_id FROM session_events WHERE message_id = ?').bind(stored.id)
      .all<{ session_id: string }>();
    const decisions = await (await SELF.fetch(`${api}/messages/${id}?replies=decisions`, { headers: headers(asker.key) }))
      .json() as { replies: { body: string }[] };
    expect({ session: stored.session_id, events: events.results.map(event => event.session_id),
      decisions: decisions.replies.map(item => item.body), parent: (await row(id)).status })
      .toEqual({ session: second, events: [second], decisions: ['Yes'], parent: 'replied' });
  });
});
