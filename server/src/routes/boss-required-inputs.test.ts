// Integration coverage for complete pending-input paging and stream lifecycle.
// Exports Vitest cases; depends on D1 fixtures and the boss HTTP routes.
// Verifies more than one keyset page and text resolution discovery.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const TOKEN = 'hb_boss_required_inputs_test_0001';
const BASE = 'http://localhost/api/boss';
const headers = { Authorization: `Bearer ${TOKEN}` };

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Required Input Boss', 'admin', TOKEN, 'required-input-boss');
});

describe('required-input discovery', () => {
  it('exhausts more than 100 tied rows and removes a resolved row', async () => {
    const prefix = `page-${Date.now()}-`;
    for (let index = 0; index < 105; index += 1) {
      await insert(`${prefix}${String(index).padStart(3, '0')}`, 'async',
        JSON.stringify({ options: ['Choose'] }), 'normal', '2026-09-23T00:00:00Z');
    }
    const first = await page();
    expect(first.messages.filter((row) => row.id.startsWith(prefix))).toHaveLength(100);
    expect(first.next_cursor).toBeTruthy();
    await env.DB.prepare("UPDATE messages SET status = 'replied' WHERE id = ?")
      .bind(`${prefix}050`).run();
    const second = await page(first.next_cursor ?? undefined);
    const ids = [...first.messages, ...second.messages].map((row) => row.id);
    expect(ids.filter((id) => id.startsWith(prefix))).toHaveLength(105);
    expect(new Set(ids).size).toBe(ids.length);
    expect(second.next_cursor).toBeNull();

    const after = await allPages();
    expect(after.filter((id) => id.startsWith(prefix))).toHaveLength(104);
    expect(after).not.toContain(`${prefix}050`);
  });

  it('finds an old blocking request beyond newer mixed history', async () => {
    const prefix = `old-${Date.now()}`;
    await insert(`${prefix}-ask`, 'blocking', null, 'low', '2026-01-01T00:00:00Z');
    for (let index = 0; index < 110; index += 1) {
      if (index % 2 === 0) {
        await insert(`${prefix}-${index}`, 'async', null, 'normal', '2026-09-23T00:00:00Z');
      } else {
        await env.DB.prepare(
          `INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
           priority, created_at) VALUES (?, ?, 'boss_to_agent', 'async', 'api',
           'Answer', 'sent', 'normal', ?)`,
        ).bind(`${prefix}-${index}`, getTestAgentId(), '2026-09-23T00:00:00Z').run();
      }
    }
    expect(await allPages()).toContain(`${prefix}-ask`);
  });

  it('accepts a NULL-expiry option and removes it from pending inputs', async () => {
    const id = `null-expiry-${Date.now()}`;
    await insert(id, 'blocking', JSON.stringify({ options: ['Proceed'] }), 'normal');
    expect(await allPages()).toContain(id);
    const reply = await SELF.fetch(`${BASE}/messages/${id}/reply`, {
      method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'Proceed' }),
    });
    expect(reply.status).toBe(201);
    expect(await allPages()).not.toContain(id);
  });

  it('discovers low priority blocking text and resolves it on the stream', async () => {
    const id = `text-${Date.now()}`;
    const stream = await SELF.fetch(`${BASE}/stream?inputs=true`, { headers });
    expect(stream.status).toBe(200);
    const reader = stream.body?.getReader();
    if (!reader) throw new Error('required-input stream has no reader');
    expect(await readUntil(reader, 'event: ready', 10_000)).toContain('event: ready');
    await insert(id, 'blocking', null, 'low');
    expect(await readUntil(reader, `"id":"${id}"`, 6_000)).toContain('event: message');
    await env.DB.prepare("UPDATE messages SET status = 'replied' WHERE id = ?").bind(id).run();
    expect(await readUntil(reader, `"id":"${id}"`, 6_000)).toContain('event: resolved');
    expect(await allPages()).not.toContain(id);
    await reader.cancel();
  });

  it('excludes informational and expired rows without priority or session filters', async () => {
    const prefix = `filter-${Date.now()}`;
    await insert(`${prefix}-note`, 'async', null, 'critical');
    await insert(`${prefix}-expired`, 'blocking', null, 'high', undefined, '2020-01-01T00:00:00Z');
    await insert(`${prefix}-choice`, 'async', JSON.stringify({ options: ['Yes'] }), 'low');
    await insert(`${prefix}-withdrawn`, 'async',
      JSON.stringify({ options: ['Yes'], options_expired: true }), 'high');
    const ids = await allPages();
    expect(ids).toContain(`${prefix}-choice`);
    expect(ids).not.toContain(`${prefix}-note`);
    expect(ids).not.toContain(`${prefix}-expired`);
    expect(ids).not.toContain(`${prefix}-withdrawn`);
  });
});

interface Page { messages: { id: string }[]; next_cursor: string | null }

async function page(cursor?: string): Promise<Page> {
  const url = new URL(`${BASE}/pending-inputs`);
  if (cursor) url.searchParams.set('cursor', cursor);
  const response = await SELF.fetch(url.toString(), { headers });
  expect(response.status).toBe(200);
  return await response.json() as Page;
}

async function allPages(): Promise<string[]> {
  const ids: string[] = [];
  let cursor: string | null = null;
  do {
    const result = await page(cursor ?? undefined);
    ids.push(...result.messages.map((row) => row.id));
    cursor = result.next_cursor;
  } while (cursor);
  return ids;
}

async function insert(
  id: string, mode: 'async' | 'blocking', metadata: string | null,
  priority: string, createdAt = '2026-09-23T00:00:00Z', expiresAt: string | null = null,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO messages
     (id, agent_id, direction, mode, channel, body, status, priority, metadata, created_at, expires_at)
     VALUES (?, ?, 'agent_to_boss', ?, 'api', 'Question', 'sent', ?, ?, ?, ?)`,
  ).bind(id, getTestAgentId(), mode, priority, metadata, createdAt, expiresAt).run();
}

async function readUntil(
  reader: ReadableStreamDefaultReader<Uint8Array>, match: string, timeout = 2_000,
): Promise<string> {
  let received = '';
  const deadline = Date.now() + timeout;
  while (!received.includes(match) && Date.now() < deadline) {
    const next = await Promise.race([
      reader.read(),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error('SSE timeout')), timeout)),
    ]);
    received += new TextDecoder().decode(next.value);
  }
  return received;
}
