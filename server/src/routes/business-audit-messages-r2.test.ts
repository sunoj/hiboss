// Round-two message regressions: forward copies of asks and agent-to-agent reply sessions.
// Covers pending-input listing, Telegram auto-link targets, and reply session events.
// Depends on SELF, seeded D1 fixtures, a mocked Telegram fetch and the forward helpers.

import { testRequest, testJson } from '../test-request';
import { env } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { createAgent } from '../agent-keys';
import { seedDatabase } from '../test-helpers';
import type { Env, MessageRow } from '../types';
import { fetchAllRequiredInputs } from './boss-required-inputs';

const api = 'https://test.local/api';
const unique = (name: string): string => `m2-${name}-${crypto.randomUUID().slice(0, 8)}`;
const headers = (key: string): Record<string, string> => ({ Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' });

async function agent(name: string): Promise<{ id: string; key: string }> {
  const created = await createAgent(env.DB, unique(name), { type: 'system', id: 'messages-r2-test' });
  if (!created) throw new Error('agent fixture missing');
  return created;
}

async function session(agentId: string): Promise<string> {
  const id = unique('session');
  await env.DB.prepare('INSERT INTO sessions (id, agent_id, label) VALUES (?, ?, ?)').bind(id, agentId, id).run();
  return id;
}

async function row(id: string): Promise<MessageRow> {
  const found = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!found) throw new Error(`message ${id} missing`);
  return found;
}

async function eventSessions(messageId: string): Promise<string[]> {
  const rows = await env.DB.prepare('SELECT session_id FROM session_events WHERE message_id = ?')
    .bind(messageId).all<{ session_id: string }>();
  return rows.results.map(event => event.session_id);
}

/** A blocking Telegram option ask with a deadline, delivered to `chat`. */
beforeAll(async () => { await seedDatabase(); });
afterEach(() => { vi.unstubAllGlobals(); });

describe('SP2 an agent-to-agent reply belongs to the replier\'s session', () => {
  it('stores the replier\'s session, targets the asker\'s session and lands the event for the replier', async () => {
    const asker = await agent('sp2-a');
    const peer = await agent('sp2-b');
    const askerSession = await session(asker.id);
    const peerSession = await session(peer.id);
    const parent = unique('parent');
    await env.DB.prepare(`INSERT INTO messages
      (id, agent_id, direction, mode, channel, body, status, session_id, target_agent_id, target_session_id)
      VALUES (?, ?, 'agent_to_agent', 'async', 'api', 'ping', 'sent', ?, ?, ?)`)
      .bind(parent, asker.id, askerSession, peer.id, peerSession).run();
    const reply = await testJson(201,
      testRequest('POST', `${api}/messages/${parent}/reply`, headers(peer.key),
        { body: 'pong' })) as MessageRow;
    // CONTROL: the reply is addressed back to the asker.
    expect({ agent: reply.agent_id, target: reply.target_agent_id }).toEqual({ agent: peer.id, target: asker.id });
    expect({ session: reply.session_id, targetSession: reply.target_session_id, events: await eventSessions(reply.id) })
      .toEqual({ session: peerSession, targetSession: askerSession, events: [peerSession] });
  });

  it('stores no session for a replier the parent does not name', async () => {
    const asker = await agent('sp2-c');
    const peer = await agent('sp2-d');
    const askerSession = await session(asker.id);
    const parent = unique('parent');
    await env.DB.prepare(`INSERT INTO messages
      (id, agent_id, direction, mode, channel, body, status, session_id, target_agent_id)
      VALUES (?, ?, 'agent_to_agent', 'async', 'api', 'ping', 'sent', ?, ?)`)
      .bind(parent, asker.id, askerSession, peer.id).run();
    const reply = await testJson(201,
      testRequest('POST', `${api}/messages/${parent}/reply`, headers(peer.key),
        { body: 'pong' })) as MessageRow;
    expect({ session: reply.session_id, targetSession: reply.target_session_id, events: await eventSessions(reply.id) })
      .toEqual({ session: null, targetSession: askerSession, events: [] });
  });
});
