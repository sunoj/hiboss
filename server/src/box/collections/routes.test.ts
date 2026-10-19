// Covers collection management, access isolation and membership ownership over HTTP.
// Uses the real Workers D1 store and existing Box authentication fixtures.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import { OWNER, OTHER, ADMIN, create, request, resetBox, seedBox } from '../../box-test-helpers';
import { getTestAgentId } from '../../test-helpers';
import { collectionList, collections, membership, newCollection } from './test-helpers';

beforeAll(seedBox);
beforeEach(() => resetBox());

it('creates, orders, renames and deletes collections while keeping items', async () => {
  const z = await newCollection(' Zed ');
  const a = await newCollection('Alpha');
  const admin = await newCollection('First', ADMIN);
  await newCollection('Private', OTHER);
  expect(z).toMatchObject({ boss_id: OWNER, boss_name: 'Box Owner', name: 'Zed',
    item_count: 0, cover_item_id: null });
  expect(z.id).toMatch(/^bc_[a-f0-9]+$/);
  expect(Number.isFinite(Date.parse(z.created_at))).toBe(true);
  expect(z.updated_at).toBe(z.created_at);
  expect((await collectionList()).map(row => row.id)).toEqual([a.id, z.id]);
  expect((await collectionList('agent')).map(row => row.id)).toEqual([admin.id, a.id, z.id]);
  const renamed = await collections(`/${z.id}`, 'PATCH', { name: ' Beta ' });
  expect(renamed.status).toBe(200);
  expect(await renamed.json()).toMatchObject({ id: z.id, name: 'Beta', created_at: z.created_at });
  const item = await create({ text: 'survives collection deletion' });
  await membership(z.id, item.id);
  expect((await collections(`/${z.id}`, 'DELETE')).status).toBe(204);
  expect(await (await request(`/${item.id}`)).json()).toMatchObject({ collection_ids: [] });
  expect(await env.DB.prepare('SELECT * FROM box_collection_items').all())
    .toMatchObject({ results: [] });
});

it('rejects case-insensitive duplicate creates and renames with 409 within a boss', async () => {
  const a = await newCollection('Alpha');
  const b = await newCollection('Beta');
  expect((await collections('', 'POST', { name: ' alpha ' })).status).toBe(409);
  expect((await collections(`/${b.id}`, 'PATCH', { name: 'ALPHA' })).status).toBe(409);
  expect((await collections(`/${a.id}`, 'PATCH', { name: 'ALPHA' })).status).toBe(200);
  expect((await newCollection('alpha', OTHER)).boss_id).toBe(OTHER);
});

it.each([null, [], {}, { name: 7 }, { name: '' }, { name: '  ' },
  { name: 'a'.repeat(65) }, { name: 'bad\nname' }, { name: '\ttrimmed' }, { name: 'bad\u007fname' }])(
  'rejects invalid create and rename names: %j', async body => {
    const collection = await newCollection('Valid');
    expect((await collections('', 'POST', body)).status).toBe(400);
    expect((await collections(`/${collection.id}`, 'PATCH', body)).status).toBe(400);
  });

it('accepts 64 Unicode characters and enforces the 200-collection limit per boss', async () => {
  await newCollection('😀'.repeat(64));
  await env.DB.batch(Array.from({ length: 199 }, (_, n) => env.DB.prepare(`INSERT INTO box_collections
    VALUES (?, ?, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')`)
    .bind(`bc_limit_${n}`, OWNER, `Limit ${n}`)));
  expect((await collections('', 'POST', { name: 'Overflow' })).status).toBe(409);
  const existing = (await collectionList())[0];
  expect((await collections(`/${existing.id}`, 'PATCH', { name: 'Rename at limit' })).status).toBe(200);
  expect((await newCollection('Other limit', OTHER)).boss_id).toBe(OTHER);
});

it('hides collection deletion from agents and cross-boss collection IDs from callers', async () => {
  const own = await newCollection('Own');
  const foreign = await newCollection('Foreign', OTHER);
  expect((await collections(`/${own.id}`, 'DELETE', undefined, 'agent')).status).toBe(404);
  for (const method of ['PATCH', 'DELETE']) {
    expect((await collections(`/${foreign.id}`, method, { name: 'Agent' }, 'agent')).status).toBe(404);
    expect((await collections(`/${foreign.id}`, method, { name: 'Cross boss' })).status).toBe(404);
    expect((await collections('/bc_missing', method, { name: 'Missing' })).status).toBe(404);
  }
});

it('lets agents organize any live item in the same readable boss collection', async () => {
  const own = await newCollection('Own');
  const foreign = await newCollection('Foreign', OTHER);
  const readable = await newCollection('Readable', ADMIN);
  const agent = await create({ text: 'mine', boss: OWNER }, 'agent');
  const boss = await create({ text: 'boss item' });
  const peer = await create({ text: 'peer item' });
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('collection-peer', 'Collection Peer', 'synthetic-collection-peer-hash').run();
  await env.DB.prepare('UPDATE box_items SET agent_id = ? WHERE id = ?')
    .bind('collection-peer', peer.id).run();
  expect((await membership(own.id, agent.id, 'PUT', 'agent')).collection_ids).toEqual([own.id]);
  expect((await membership(own.id, agent.id, 'DELETE', 'agent')).collection_ids).toEqual([]);
  for (const item of [boss, peer]) {
    expect((await membership(own.id, item.id, 'PUT', 'agent')).collection_ids).toEqual([own.id]);
    expect((await membership(own.id, item.id, 'DELETE', 'agent')).collection_ids).toEqual([]);
  }
  const hidden = await create({ text: 'hidden' }, OTHER);
  for (const method of ['PUT', 'DELETE']) {
    for (const [collection, item] of [[foreign.id, hidden.id], [own.id, hidden.id], [foreign.id, agent.id],
      [readable.id, agent.id], [own.id, 'bx_missing'], ['bc_missing', agent.id]]) {
      const response = await collections(`/${collection}/items/${item}`, method, undefined, 'agent');
      expect(response.status).toBe(404);
    }
  }
  for (const method of ['PUT', 'DELETE']) {
    expect((await collections(`/${foreign.id}/items/${boss.id}`, method)).status).toBe(404);
  }
  expect((await collections(`/${readable.id}/items/${boss.id}`, 'PUT', undefined, ADMIN)).status).toBe(404);
  expect((await membership(own.id, agent.id)).collection_ids).toEqual([own.id]);
  await request(`/${agent.id}`, 'DELETE', undefined, 'agent');
  expect((await collections(`/${own.id}/items/${agent.id}`, 'PUT', undefined, 'agent')).status).toBe(404);
  expect(await env.DB.prepare('SELECT agent_id FROM box_items WHERE id = ?').bind(agent.id).first())
    .toEqual({ agent_id: getTestAgentId() });
});

it('makes memberships idempotent and returns collection IDs oldest membership first', async () => {
  const a = await newCollection('First');
  const b = await newCollection('Second');
  const item = await create({ text: 'member' });
  await membership(b.id, item.id);
  await env.DB.prepare('UPDATE box_collection_items SET added_at = ? WHERE item_id = ?')
    .bind('2020-01-01T00:00:00.000Z', item.id).run();
  await membership(a.id, item.id);
  expect((await membership(b.id, item.id)).collection_ids).toEqual([b.id, a.id]);
  expect(await env.DB.prepare('SELECT added_at FROM box_collection_items WHERE collection_id = ?')
    .bind(b.id).first()).toEqual({ added_at: '2020-01-01T00:00:00.000Z' });
  for (let n = 0; n < 2; n++) {
    expect((await membership(a.id, item.id, 'DELETE')).collection_ids).toEqual([b.id]);
  }
  expect((await collectionList()).find(row => row.id === b.id)?.item_count).toBe(1);
});

it('rejects malformed JSON for collection creation and rename', async () => {
  const collection = await newCollection('Valid');
  for (const [path, method] of [['', 'POST'], [`/${collection.id}`, 'PATCH']]) {
    const response = await SELF.fetch(`https://test.local/api/box/collections${path}`, {
      method, headers: { Authorization: `Bearer ${OWNER}`, 'Content-Type': 'application/json' },
      body: '{',
    });
    expect(response.status).toBe(400);
  }
});
