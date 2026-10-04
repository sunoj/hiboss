// Tests session identity on /api/sessions: host, runtime, dispatch_ref and the
// same-device rule for parent_session_id.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { parseSessionIdentity } from './session-identity';

// Agents: main + sibling share device d-one; foreign is on d-two; legacy has no device.
const AGENTS = [
  { id: 'ident-main', key: 'hb_test_key_ident_main_000000', device: 'd-one' },
  { id: 'ident-sibling', key: 'hb_test_key_ident_sibling_000', device: 'd-one' },
  { id: 'ident-foreign', key: 'hb_test_key_ident_foreign_000', device: 'd-two' },
  { id: 'ident-legacy', key: 'hb_test_key_ident_legacy_0000', device: null },
] as const;
type AgentId = typeof AGENTS[number]['id'];

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT INTO devices (id, label) VALUES ('d-one', 'one'), ('d-two', 'two')").run();
  for (const agent of AGENTS) {
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash, device_id) VALUES (?, ?, ?, ?)')
      .bind(agent.id, agent.id, await hashApiKey(agent.key), agent.device).run();
  }
});

async function register(agentId: AgentId, body: Record<string, unknown>): Promise<Response> {
  const agent = AGENTS.find(a => a.id === agentId)!;
  return SELF.fetch('http://localhost/api/sessions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${agent.key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ project: agentId, ...body }),
  });
}

async function storedParent(id: string): Promise<string | null> {
  return env.DB.prepare('SELECT parent_session_id FROM sessions WHERE id = ?').bind(id).first<string | null>('parent_session_id');
}

describe('session identity fields', () => {
  it('stores host, runtime and dispatch_ref and returns them', async () => {
    const res = await register('ident-main', { id: 'ident-root', host: 'mini', runtime: 'claude' });
    expect(res.status).toBe(201);
    const data = await res.json() as Record<string, unknown>;
    expect(data).toMatchObject({ host: 'mini', runtime: 'claude', dispatch_ref: null, parent_session_id: null });
    expect(data).not.toHaveProperty('parent_rejected');
    const row = await env.DB.prepare('SELECT host, runtime, dispatch_ref FROM sessions WHERE id = ?').bind('ident-root').first();
    expect(row).toEqual({ host: 'mini', runtime: 'claude', dispatch_ref: null });
  });

  it('rejects malformed identity fields', async () => {
    expect((await register('ident-main', { id: 'ident-bad-1', runtime: 'Claude Code' })).status).toBe(400);
    expect((await register('ident-main', { id: 'ident-bad-2', host: 'a b' })).status).toBe(400);
    expect((await register('ident-main', { id: 'ident-bad-3', dispatch_ref: 7 })).status).toBe(400);
  });

  it('lists the identity fields', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', { headers: { Authorization: `Bearer ${AGENTS[0].key}` } });
    const { sessions } = await res.json() as { sessions: Record<string, unknown>[] };
    expect(sessions.find(s => s.id === 'ident-root')).toMatchObject({ host: 'mini', runtime: 'claude' });
  });
});

describe('parent_session_id', () => {
  it('accepts a parent whose agent is on the same device', async () => {
    const res = await register('ident-sibling', { id: 'ident-child', runtime: 'aid', dispatch_ref: 't-1', parent_session_id: 'ident-root' });
    expect(res.status).toBe(201);
    const data = await res.json() as Record<string, unknown>;
    expect(data).toMatchObject({ parent_session_id: 'ident-root', dispatch_ref: 't-1' });
    expect(data).not.toHaveProperty('parent_rejected');
    expect(await storedParent('ident-child')).toBe('ident-root');
  });

  it('drops a parent on another device and says so', async () => {
    const data = await (await register('ident-foreign', { id: 'ident-foreign-child', parent_session_id: 'ident-root' })).json() as Record<string, unknown>;
    expect(data).toMatchObject({ parent_session_id: null, parent_rejected: true });
    expect(await storedParent('ident-foreign-child')).toBeNull();
  });

  it('drops a parent when the caller has no device', async () => {
    const data = await (await register('ident-legacy', { id: 'ident-legacy-child', parent_session_id: 'ident-root' })).json() as Record<string, unknown>;
    expect(data.parent_rejected).toBe(true);
  });

  it('drops an unknown parent, itself, and a parent that has a parent', async () => {
    for (const [id, parent] of [['ident-u', 'no-such-session'], ['ident-self', 'ident-self'], ['ident-grand', 'ident-child']]) {
      const data = await (await register('ident-main', { id, parent_session_id: parent })).json() as Record<string, unknown>;
      expect(data.parent_rejected, `${id} -> ${parent}`).toBe(true);
      expect(await storedParent(id)).toBeNull();
    }
  });

  it('cannot close a cycle', async () => {
    const data = await (await register('ident-main', { id: 'ident-root', parent_session_id: 'ident-child' })).json() as Record<string, unknown>;
    expect(data.parent_rejected).toBe(true);
    expect(await storedParent('ident-root')).toBeNull();
  });

  it('refuses a parent to a session that already has children', async () => {
    await register('ident-main', { id: 'ident-other-root' });
    const data = await (await register('ident-main', { id: 'ident-root', parent_session_id: 'ident-other-root' })).json() as Record<string, unknown>;
    expect(data).toMatchObject({ parent_session_id: null, parent_rejected: true });
    expect(await storedParent('ident-child')).toBe('ident-root');
  });

  it('forms no cycle when two sessions name each other concurrently', async () => {
    for (let round = 0; round < 10; round++) {
      const [a, b] = [`ident-race-a-${round}`, `ident-race-b-${round}`];
      await register('ident-main', { id: a });
      await register('ident-sibling', { id: b });
      await Promise.all([
        register('ident-main', { id: a, parent_session_id: b }),
        register('ident-sibling', { id: b, parent_session_id: a }),
      ]);
      const parents = [await storedParent(a), await storedParent(b)];
      expect(parents.filter(p => p !== null).length, `round ${round}`).toBeLessThanOrEqual(1);
    }
  });

  it('clears a child pointer when the parent is deleted', async () => {
    await register('ident-main', { id: 'ident-root-2' });
    await register('ident-sibling', { id: 'ident-child-2', parent_session_id: 'ident-root-2' });
    expect(await storedParent('ident-child-2')).toBe('ident-root-2');
    await SELF.fetch('http://localhost/api/sessions/ident-root-2', { method: 'DELETE', headers: { Authorization: `Bearer ${AGENTS[0].key}` } });
    expect(await storedParent('ident-child-2')).toBeNull();
  });
});

describe('parseSessionIdentity', () => {
  it('treats blank and missing fields as absent', () => {
    expect(parseSessionIdentity({ host: '  ', runtime: undefined })).toEqual({ host: null, runtime: null, dispatchRef: null, parentSessionId: null });
  });

  it('accepts runtimes it does not know yet', () => {
    expect(parseSessionIdentity({ runtime: 'codex' })).toMatchObject({ runtime: 'codex' });
  });

  it('rejects an over-long dispatch_ref', () => {
    expect(parseSessionIdentity({ dispatch_ref: 'x'.repeat(129) })).toBe('dispatch_ref is malformed');
  });
});
