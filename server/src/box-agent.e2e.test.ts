// Exercises agent Box contributions through real HTTP, D1 and private R2 routes.
// Covers target selection, provenance, author ownership, retries and read filters.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, expect, it } from 'vitest';
import {
  ADMIN, OWNER, OTHER, create, page, request, resetBox, seedBox, upload, type Item,
} from './box-test-helpers';
import { getTestAgentId } from './test-helpers';
import { hashApiKey } from './middleware/auth';

const PEER = 'synthetic-box-peer-key';
const PEER_ID = 'box-peer-agent';
const AUTHOR = { kind: 'agent', id: getTestAgentId(), name: 'test-agent' };

beforeAll(async () => {
  await seedBox();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(PEER_ID, 'Box Peer', await hashApiKey(PEER)).run();
});

beforeEach(() => resetBox([getTestAgentId(), PEER_ID]));
afterEach(() => resetBox([getTestAgentId(), PEER_ID]));

it('adds agent text, links and private files to the sole resolved boss without a target', async () => {
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(ADMIN).run();
  for (const body of [{ text: 'agent reference' }, { url: 'https://example.invalid/agent' }]) {
    const item = await create(body, 'agent');
    expect(item).toMatchObject({ boss_id: OWNER, added_by: AUTHOR, source: 'cli' });
  }
  const response = await upload('application/pdf', 4, { source: 'cli' }, 'agent');
  expect(response.status).toBe(201);
  const item = await response.json() as Item;
  expect(item).toMatchObject({ kind: 'file', media_bytes: 4, added_by: AUTHOR });
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${item.id}`)).not.toBeNull();
  expect((await request(`/${item.id}/media`, 'GET', undefined, 'agent')).status).toBe(200);
  const publicMedia = await SELF.fetch(`https://test.local/api/attachments/box/${OWNER}/${item.id}`);
  expect(publicMedia.status).toBe(404);
});

it('returns 409 naming every resolved boss when an agent omits a multi-boss target', async () => {
  const response = await request('', 'POST', { text: 'ambiguous' }, 'agent');
  expect(response.status).toBe(409);
  const message = await response.text();
  for (const choice of ['Box Owner', OWNER, 'Box Admin', ADMIN]) expect(message).toContain(choice);
  expect(message).not.toContain('Box Other');
  expect(await env.DB.prepare("SELECT id FROM box_items WHERE text = 'ambiguous'").first()).toBeNull();
});

it.each([OWNER, 'Box Owner', ADMIN, 'Box Admin'].flatMap(boss =>
  ['agent', PEER].map(token => ({ boss, token }))))(
  'selects a resolved JSON upload boss by id or name: $boss with $token', async ({ boss, token }) => {
    const item = await create({ text: 'targeted', boss }, token);
    expect(item.boss_id).toBe(boss === OWNER || boss === 'Box Owner' ? OWNER : ADMIN);
    expect(item.added_by).toEqual(token === 'agent' ? AUTHOR
      : { kind: 'agent', id: PEER_ID, name: 'Box Peer' });
  });

it.each([OWNER, 'Box Owner', ADMIN, 'Box Admin'])('selects the peer multipart target from meta: %s',
  async boss => {
    const response = await upload('image/png', 4, { boss }, PEER);
    expect(response.status).toBe(201);
    const item = await response.json() as Item;
    expect(item).toMatchObject({ boss_id: boss === OWNER || boss === 'Box Owner' ? OWNER : ADMIN,
      added_by: { kind: 'agent', id: PEER_ID, name: 'Box Peer' } });
    expect((await request(`/${item.id}/media`, 'GET', undefined, PEER)).status).toBe(200);
  });

it('returns identical 404s for foreign and nonexistent upload bosses', async () => {
  const bodies: string[] = [];
  for (const boss of [OTHER, 'Box Other', 'missing-boss']) {
    const response = await request('', 'POST', { text: 'hidden', boss }, 'agent');
    expect(response.status).toBe(404);
    bodies.push(await response.text());
  }
  expect(new Set(bodies).size).toBe(1);
});

it('returns 404 with no resolved bosses even when an upload names a real boss', async () => {
  await env.DB.prepare('DELETE FROM boss_agent_access WHERE agent_id = ?').bind(getTestAgentId()).run();
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(ADMIN).run();
  for (const boss of [undefined, OWNER]) {
    expect((await request('', 'POST', { text: 'unreachable', boss }, 'agent')).status).toBe(404);
  }
});

it('includes boss or agent provenance in create, replay, show, latest, list, search and patch responses',
  async () => {
    const boss = await create({ text: 'provenanceneedle', project: 'provenance' });
    expect(boss.added_by).toEqual({ kind: 'boss' });
    const body = { text: 'provenanceneedle', project: 'provenance', boss: OWNER };
    const headers = { 'Idempotency-Key': 'provenance-key' };
    const created = await request('', 'POST', body, 'agent', headers);
    expect(created.status).toBe(201);
    const agent = await created.json() as Item;
    expect(agent.added_by).toEqual(AUTHOR);
    expect(agent).not.toHaveProperty('agent_id');
    expect(agent).not.toHaveProperty('agent_name');
    const replay = await request('', 'POST', body, 'agent', headers);
    expect(await replay.json()).toEqual(agent);
    for (const path of [`/${agent.id}`, '/latest?project=provenance&by=agent']) {
      expect(await (await request(path, 'GET', undefined, 'agent')).json()).toEqual(agent);
    }
    for (const path of ['?project=provenance', '/search?q=provenanceneedle&project=provenance']) {
      const items = (await page(path, 'agent')).items;
      expect(items).toHaveLength(2);
      expect(items.find(item => item.id === boss.id)?.added_by).toEqual({ kind: 'boss' });
      expect(items.find(item => item.id === agent.id)?.added_by).toEqual(AUTHOR);
    }
    const patched = await request(`/${agent.id}`, 'PATCH', { note: 'caption' }, 'agent');
    expect(patched.status).toBe(200);
    expect(await patched.json()).toMatchObject({ added_by: AUTHOR, note: 'caption' });
  });

it('lets agents patch, soft delete and purge only their own items', async () => {
  const own = await (await upload('image/png', 4, { boss: OWNER }, 'agent')).json() as Item;
  const boss = await create({ text: 'boss-owned' });
  const peer = await create({ text: 'peer-owned', boss: OWNER }, PEER);
  for (const item of [boss, peer]) {
    for (const [method, suffix] of [['PATCH', ''], ['DELETE', ''], ['DELETE', '?purge=1']]) {
      expect((await request(`/${item.id}${suffix}`, method,
        method === 'PATCH' ? { note: 'forbidden' } : undefined, 'agent')).status).toBe(404);
    }
    expect(await (await request(`/${item.id}`)).json()).toEqual(item);
  }
  const patch = await request(`/${own.id}`, 'PATCH', { tags: ['ownneedle'], project: 'own' }, 'agent');
  expect(patch.status).toBe(200);
  expect((await request(`/${own.id}`, 'PATCH', { agent_id: PEER_ID }, 'agent')).status).toBe(400);
  expect((await page('/search?q=ownneedle', 'agent')).items[0].id).toBe(own.id);
  expect((await request(`/${own.id}`, 'DELETE', undefined, 'agent')).status).toBe(204);
  expect((await request(`/${own.id}`, 'GET', undefined, 'agent')).status).toBe(404);
  expect((await page('/search?q=ownneedle', 'agent')).items).toEqual([]);
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${own.id}`)).not.toBeNull();
  expect((await request(`/${own.id}?purge=1`, 'DELETE', undefined, PEER)).status).toBe(404);
  expect((await request(`/${own.id}?purge=1`, 'DELETE', undefined, 'agent')).status).toBe(204);
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${own.id}`)).toBeNull();
  expect(await env.DB.prepare('SELECT id FROM box_items WHERE id = ?').bind(own.id).first()).toBeNull();
});

it('preserves boss control of agent items and ignores upload author and target spoofing', async () => {
  const agent = await create({ text: 'agent-owned', boss: OWNER, agent_id: PEER_ID,
    added_by: { kind: 'boss' } }, 'agent');
  expect(agent.added_by).toEqual(AUTHOR);
  expect((await request(`/${agent.id}`, 'PATCH', { note: 'boss edit' })).status).toBe(200);
  expect((await request(`/${agent.id}?purge=1`, 'DELETE')).status).toBe(204);
  const boss = await create({ text: 'boss-owned', boss: OTHER, agent_id: PEER_ID });
  expect(boss).toMatchObject({ boss_id: OWNER, added_by: { kind: 'boss' } });
});

it('isolates concurrent idempotency retries across the boss and each agent in the same Box', async () => {
  const key = 'shared-key';
  const ids: string[] = [];
  for (const token of [OWNER, 'agent', PEER]) {
    const body = { text: `retry ${token}`, boss: OWNER };
    const headers = { 'Idempotency-Key': key };
    const replies = await Promise.all([request('', 'POST', body, token, headers),
      request('', 'POST', body, token, headers)]);
    expect(replies.map(reply => reply.status)).toEqual([201, 201]);
    const items = await Promise.all(replies.map(reply => reply.json() as Promise<Item>));
    expect(items[0]).toEqual(items[1]);
    expect(items[0].added_by).toEqual(token === OWNER ? { kind: 'boss' }
      : token === 'agent' ? AUTHOR : { kind: 'agent', id: PEER_ID, name: 'Box Peer' });
    ids.push(items[0].id);
  }
  expect(new Set(ids).size).toBe(3);
  const bossRetry = await env.DB.prepare('SELECT item_id FROM box_idempotency').all();
  expect(bossRetry.results).toEqual([{ item_id: ids[0] }]);
  const agentRetries = await env.DB.prepare('SELECT item_id FROM box_agent_idempotency')
    .all<{ item_id: string }>();
  expect(agentRetries.results.map(row => row.item_id).sort()).toEqual(ids.slice(1).sort());
  const otherBox = await request('', 'POST', { text: 'other box', boss: ADMIN }, 'agent',
    { 'Idempotency-Key': key });
  expect(otherBox.status).toBe(201);
  expect(ids).not.toContain((await otherBox.json() as Item).id);
  expect((await request(`/${ids[1]}?purge=1`, 'DELETE', undefined, 'agent')).status).toBe(204);
  expect((await request('', 'POST', { text: 'retry', boss: OWNER }, 'agent',
    { 'Idempotency-Key': key })).status).toBe(404);
});

it('deduplicates agent multipart retries without leaving objects outside the target Box', async () => {
  const replies = await Promise.all([upload('image/png', 4, { boss: OWNER }, 'agent', 'agent-media'),
    upload('image/png', 4, { boss: OWNER }, 'agent', 'agent-media')]);
  expect(replies.map(reply => reply.status)).toEqual([201, 201]);
  const items = await Promise.all(replies.map(reply => reply.json() as Promise<Item>));
  expect(items[0]).toEqual(items[1]);
  const objects = await env.ATTACHMENTS.list({ prefix: `box/${OWNER}/` });
  expect(objects.objects.map(object => object.key)).toEqual([`box/${OWNER}/${items[0].id}`]);
});

it('keeps resolvedBosses scoping for an agent own item after its grant is revoked', async () => {
  const item = await create({ text: 'revokedneedle', boss: OWNER }, 'agent');
  await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ? AND agent_id = ?')
    .bind(OWNER, getTestAgentId()).run();
  for (const method of ['GET', 'PATCH', 'DELETE']) {
    expect((await request(`/${item.id}`, method,
      method === 'PATCH' ? { note: 'revoked' } : undefined, 'agent')).status).toBe(404);
  }
  expect((await request(`/${item.id}?purge=1`, 'DELETE', undefined, 'agent')).status).toBe(404);
  expect((await page('/search?q=revokedneedle&by=agent', 'agent')).items).toEqual([]);
});

it.each(['', '/search?q=filterneedle'])('filters by boss or agent before paginating %s', async path => {
  const boss = await create({ text: 'filterneedle', project: 'by-filter' });
  const agent = await create({ text: 'filterneedle', project: 'by-filter', boss: OWNER }, 'agent');
  const peer = await create({ text: 'filterneedle', project: 'by-filter', boss: OWNER }, PEER);
  await create({ text: 'filterneedle', project: 'by-filter' }, OTHER);
  const query = `${path}${path ? '&' : '?'}project=by-filter&boss=Box%20Owner`;
  for (const token of [OWNER, 'agent']) {
    expect((await page(query, token)).items).toHaveLength(3);
    expect((await page(`${query}&by=boss`, token)).items).toEqual([boss]);
    const first = await page(`${query}&by=agent&limit=1`, token);
    expect(first.next_cursor).not.toBeNull();
    const next = await page(`${query}&by=agent&limit=1&cursor=${first.next_cursor}`, token);
    expect(next.next_cursor).toBeNull();
    expect([...first.items, ...next.items].map(item => item.id).sort()).toEqual([agent.id, peer.id].sort());
  }
});

it('filters latest by author and rejects invalid by values on every read collection', async () => {
  const boss = await create({ text: 'latestneedle', project: 'by-latest' });
  const agent = await create({ text: 'latestneedle', project: 'by-latest', boss: OWNER }, 'agent');
  for (const token of [OWNER, 'agent']) {
    for (const [by, expected] of [['boss', boss], ['agent', agent]] as const) {
      const response = await request(`/latest?project=by-latest&by=${by}`, 'GET', undefined, token);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual(expected);
    }
    for (const path of ['?by=other', '/latest?by=other', '/search?q=needle&by=other']) {
      expect((await request(path, 'GET', undefined, token)).status).toBe(400);
    }
  }
  await request(`/${boss.id}`, 'DELETE');
  expect((await request('/latest?project=by-latest&by=boss')).status).toBe(404);
});

it.each(['text', 'note'])('enforces the same agent %s byte limit as boss uploads', async field => {
  expect((await request('', 'POST', { boss: OWNER, text: 'valid', [field]: 'x'.repeat(16385) },
    'agent')).status).toBe(413);
});

it.each([['image/png', 10], ['video/mp4', 50], ['application/pdf', 50]] as const)(
  'enforces the same agent %s size and kind limits as boss uploads', async (type, megabytes) => {
    expect((await upload(type, megabytes * 1024 * 1024 + 1, { boss: OWNER }, 'agent')).status).toBe(413);
    const response = await upload(type, 4, { boss: OWNER }, 'agent');
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ kind: type.startsWith('image/') ? 'image'
      : type.startsWith('video/') ? 'video' : 'file', added_by: AUTHOR });
  });
