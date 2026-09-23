// Regression coverage for unread isolation and authorization after SSE connection.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedDatabase, authHeaders, seedBossToken } from '../test-helpers';
import { createAgent } from '../agent-keys';
import { issueBossToken } from '../boss-token';

beforeAll(seedDatabase);
const base = 'https://test.local/api';

it.each(['', '&direction=agent_to_agent'])('isolates unread messages and totals with a foreign target session%s', async suffix => {
  const victim = await createAgent(env.DB, `unread-victim-${suffix}`, { type: 'system', id: 'test' });
  const sender = await createAgent(env.DB, `unread-sender-${suffix}`, { type: 'system', id: 'test' });
  if (!victim || !sender) throw new Error('fixture failed');
  const session = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, victim.id).run();
  await env.DB.prepare(`INSERT INTO messages (agent_id, direction, mode, body, target_agent_id, target_session_id)
    VALUES (?, 'agent_to_agent', 'async', 'private unread content', ?, ?)`)
    .bind(sender.id, victim.id, session).run();
  const path = `${base}/messages?unread=true&target_session=${session}${suffix}`;
  const response = await SELF.fetch(path, { headers: authHeaders() });
  expect(await response.json()).toEqual({ messages: [], total: 0 });
  const allowed = await SELF.fetch(path, { headers: { Authorization: `Bearer ${victim.key}` } });
  expect(await allowed.json()).toMatchObject({ total: 1, messages: [{ body: 'private unread content' }] });
});

it('stops an established agent stream after its credential is revoked', async () => {
  const agent = await createAgent(env.DB, 'stream-revocation', { type: 'system', id: 'test' });
  if (!agent) throw new Error('fixture failed');
  const insert = (body: string) => env.DB.prepare(`INSERT INTO messages (agent_id, direction, mode, body, created_at)
    VALUES (?, 'boss_to_agent', 'async', ?, datetime('now', '+1 minute'))`).bind(agent.id, body).run();
  await insert('before revocation');
  const response = await SELF.fetch(`${base}/messages/stream`, { headers: { Authorization: `Bearer ${agent.key}` } });
  const reader = response.body!.getReader();
  try {
    expect(new TextDecoder().decode((await reader.read()).value)).toContain('before revocation');
    await env.DB.prepare("UPDATE agent_keys SET revoked_at = datetime('now') WHERE agent_id = ?").bind(agent.id).run();
    await insert('after revocation');
    expect((await reader.read()).done).toBe(true);
    expect(await env.DB.prepare('SELECT status FROM messages WHERE agent_id = ? AND body = ?')
      .bind(agent.id, 'after revocation').first()).toEqual({ status: 'sent' });
  } finally {
    await reader.cancel();
  }
});

it.each([
  ['?feed=true', 'token'], ['?feed=true', 'client'], ['?feed=true', 'role'], ['?feed=true', 'grant'],
  ['', 'token'], ['', 'grant'], ['?options=true', 'token'], ['?options=true', 'grant'],
])('stops boss stream %s after revoking its %s', async (query, change) => {
  const id = crypto.randomUUID();
  const agent = await createAgent(env.DB, id, { type: 'system', id: 'test' });
  if (!agent) throw new Error('fixture failed');
  const bossId = await seedBossToken(id, 'manager', `seed-${id}`);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?), (?, ?)')
    .bind(bossId, agent.id, bossId, 'test-agent-id').run();
  const grant = await issueBossToken(env, bossId, 'stream', undefined, { kind: 'web', label: 'stream' });
  const insert = (body: string) => env.DB.prepare(`INSERT INTO messages
    (agent_id, direction, mode, body, metadata, expires_at, created_at)
    VALUES (?, 'agent_to_boss', 'blocking', ?, '{"options":["Approve"]}',
      datetime('now', '+1 hour'), datetime('now', '+1 minute'))`).bind(agent.id, body).run();
  // Option timestamps use the API's ISO format.
  await insert('before revocation');
  await env.DB.prepare('UPDATE messages SET expires_at = ? WHERE agent_id = ?')
    .bind(new Date(Date.now() + 3_600_000).toISOString(), agent.id).run();
  const response = await SELF.fetch(`${base}/boss/stream${query}`, { headers: { Authorization: `Bearer ${grant.token}` } });
  expect(response.status).toBe(200);
  const reader = response.body!.getReader();
  try {
    expect(new TextDecoder().decode((await reader.read()).value)).toContain('before revocation');
    if (change === 'token') await env.DB.prepare("UPDATE boss_tokens SET revoked_at = datetime('now') WHERE id = ?").bind(grant.tokenId).run();
    if (change === 'client') await env.DB.prepare("UPDATE boss_clients SET revoked_at = datetime('now') WHERE id = ?").bind(grant.clientId).run();
    if (change === 'role') await env.DB.prepare("UPDATE bosses SET role = 'viewer' WHERE id = ?").bind(bossId).run();
    if (change === 'grant') await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ? AND agent_id = ?').bind(bossId, agent.id).run();
    await insert('after revocation');
    await env.DB.prepare('UPDATE messages SET expires_at = ? WHERE agent_id = ?')
      .bind(new Date(Date.now() + 3_600_000).toISOString(), agent.id).run();
    expect((await reader.read()).done).toBe(true);
    expect(await env.DB.prepare('SELECT status FROM messages WHERE agent_id = ? AND body = ?')
      .bind(agent.id, 'after revocation').first()).toEqual({ status: 'sent' });
  } finally {
    await reader.cancel();
  }
});

it.each(['agent-key', 'boss-token', 'boss-grant'])('stops a session event stream after %s revocation', async change => {
  const id = crypto.randomUUID();
  const agent = await createAgent(env.DB, id, { type: 'system', id: 'test' });
  if (!agent) throw new Error('fixture failed');
  const bossId = await seedBossToken(id, 'manager', `boss-${id}`);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(bossId, agent.id).run();
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(id, agent.id).run();
  const append = (sequence: number) => env.DB.prepare(`INSERT INTO session_events (session_id, sequence, kind, raw)
    VALUES (?, ?, 'message', ?)` ).bind(id, sequence, JSON.stringify({ body: `event-${sequence}` })).run();
  await append(1);
  const token = change === 'agent-key' ? agent.key : `boss-${id}`;
  const response = await SELF.fetch(`${base}/sessions/${id}/stream?after=0`, { headers: { Authorization: `Bearer ${token}` } });
  expect(response.status).toBe(200);
  const reader = response.body!.getReader();
  try {
    expect(new TextDecoder().decode((await reader.read()).value)).toContain('event-1');
    if (change === 'agent-key') await env.DB.prepare("UPDATE agent_keys SET revoked_at = datetime('now') WHERE agent_id = ?").bind(agent.id).run();
    if (change === 'boss-token') await env.DB.prepare("UPDATE boss_tokens SET revoked_at = datetime('now') WHERE boss_id = ?").bind(bossId).run();
    if (change === 'boss-grant') await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ?').bind(bossId).run();
    await append(2);
    expect((await reader.read()).done).toBe(true);
  } finally {
    await reader.cancel();
  }
});

it('rejects a pending blocking poll after its agent credential is revoked', async () => {
  const id = crypto.randomUUID();
  const agent = await createAgent(env.DB, id, { type: 'system', id: 'test' });
  if (!agent) throw new Error('fixture failed');
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, body)
    VALUES (?, ?, 'agent_to_boss', 'blocking', 'question')`).bind(id, agent.id).run();
  let settled = false;
  const pending = SELF.fetch(`${base}/messages/${id}/poll?timeout=3`, {
    method: 'POST', headers: { Authorization: `Bearer ${agent.key}` },
  }).then(response => { settled = true; return response; });
  await new Promise(resolve => setTimeout(resolve, 100));
  expect(settled).toBe(false);
  await env.DB.prepare("UPDATE agent_keys SET revoked_at = datetime('now') WHERE agent_id = ?").bind(agent.id).run();
  await env.DB.prepare(`INSERT INTO messages (agent_id, direction, mode, body, reply_to)
    VALUES (?, 'boss_to_agent', 'async', 'private reply', ?)`).bind(agent.id, id).run();
  expect((await pending).status).toBe(401);
});
