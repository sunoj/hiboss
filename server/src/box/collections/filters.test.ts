// Exercises collection resolution and composable liked/collection item filters.
// Uses real HTTP queries including pagination, FTS and readable multi-boss scope.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import { ADMIN, OTHER, OWNER, create, page, request, resetBox, seedBox } from '../../box-test-helpers';
import { getTestAgentId } from '../../test-helpers';
import { collectionList, membership, newCollection } from './test-helpers';

beforeAll(seedBox);
beforeEach(() => resetBox());

it('combines liked/collection with existing filters and recency pagination', async () => {
  const collection = await newCollection('Combined');
  const matching: string[] = [];
  for (const day of [2, 3]) {
    const item = await create({ text: 'filterneedle', boss: OWNER, project: 'match' }, 'agent');
    await env.DB.prepare('UPDATE box_items SET created_at = ? WHERE id = ?')
      .bind(`2026-01-0${day}T00:00:00.000Z`, item.id).run();
    await membership(collection.id, item.id);
    await request(`/${item.id}/like`, 'PUT');
    matching.unshift(item.id);
  }
  const excluded = [
    { body: { text: 'filterneedle', project: 'match' }, token: OWNER, member: true, liked: true },
    { body: { text: 'filterneedle', project: 'other', boss: OWNER }, member: true, liked: true },
    { body: { url: 'https://example.invalid/filterneedle', project: 'match', boss: OWNER },
      member: true, liked: true },
    { body: { text: 'filterneedle', project: 'match', boss: OWNER }, member: false, liked: true },
    { body: { text: 'filterneedle', project: 'match', boss: OWNER }, member: true, liked: false },
  ];
  for (const entry of excluded) {
    const item = await create(entry.body, entry.token ?? 'agent');
    if (entry.member) await membership(collection.id, item.id);
    if (entry.liked) await request(`/${item.id}/like`, 'PUT');
  }
  const old = await create({ text: 'filterneedle', project: 'match', boss: OWNER }, 'agent');
  await membership(collection.id, old.id);
  await request(`/${old.id}/like`, 'PUT');
  await env.DB.prepare('UPDATE box_items SET created_at = ? WHERE id = ?')
    .bind('2025-01-01T00:00:00.000Z', old.id).run();
  const query = `liked=1&collection=${collection.id}&kind=text&by=agent&project=match`
    + '&boss=Box%20Owner&since=2026-01-01T00:00:00Z&limit=1';
  for (const prefix of ['?', '/search?q=filterneedle&']) {
    const first = await page(prefix + query, 'agent');
    expect(first.items.map(row => row.id)).toEqual(matching.slice(0, 1));
    expect(first.next_cursor).toMatch(/^[A-Za-z0-9_-]+$/);
    const second = await page(`${prefix}${query}&cursor=${first.next_cursor}`, 'agent');
    expect(second.items.map(row => row.id)).toEqual(matching.slice(1));
    expect(second.next_cursor).toBeNull();
  }
  const latest = await request(`/latest?${query}`, 'GET', undefined, 'agent');
  expect(await latest.json()).toMatchObject({ id: matching[0] });
});

it('resolves names without case sensitivity, prefers exact IDs and hides unknown collections', async () => {
  const collection = await newCollection('Reference');
  const item = await create({ text: 'resolvedneedle' });
  await membership(collection.id, item.id);
  await newCollection(collection.id, ADMIN);
  for (const value of ['rEfErEnCe', collection.id]) {
    expect((await page(`?collection=${value}`, 'agent')).items.map(row => row.id)).toEqual([item.id]);
    expect((await page(`/search?q=resolvedneedle&collection=${value}`, 'agent')).items[0].id).toBe(item.id);
    expect(await (await request(`/latest?collection=${value}`, 'GET', undefined, 'agent')).json())
      .toMatchObject({ id: item.id });
  }
  const hidden = await newCollection('Hidden', OTHER);
  for (const value of ['missing', hidden.id, hidden.name, '']) {
    for (const prefix of ['?collection=', '/latest?collection=', '/search?q=needle&collection=']) {
      expect((await request(prefix + value, 'GET', undefined, 'agent')).status).toBe(404);
    }
  }
});

it('reports ambiguous readable names with choices but excludes inaccessible bosses', async () => {
  const owner = await newCollection('Shared');
  const admin = await newCollection('SHARED', ADMIN);
  const hidden = await newCollection('Shared', OTHER);
  for (const path of ['?collection=shared', '/latest?collection=shared',
    '/search?q=needle&collection=shared']) {
    const response = await request(path, 'GET', undefined, 'agent');
    expect(response.status).toBe(409);
    const message = await response.text();
    for (const value of [owner.id, admin.id, 'Box Owner', 'Box Admin']) expect(message).toContain(value);
    expect(message).not.toContain(hidden.id);
    expect((await request(path)).status).toBe(path.includes('latest') ? 404 : 200);
  }
  expect((await page(`?collection=${owner.id}&boss=${ADMIN}`, 'agent')).items).toEqual([]);
});

it('supports each filter alone and hides all collections when no bosses are readable', async () => {
  const collection = await newCollection('Alone');
  const liked = await create({ text: 'likedneedle' });
  const member = await create({ text: 'memberneedle' });
  await request(`/${liked.id}/like`, 'PUT');
  await membership(collection.id, member.id);
  expect((await page('?liked=1', 'agent')).items.map(row => row.id)).toEqual([liked.id]);
  expect((await page(`?collection=${collection.id}`, 'agent')).items.map(row => row.id)).toEqual([member.id]);
  expect((await page(`?collection=${collection.id}&liked=1`)).items).toEqual([]);
  await env.DB.prepare('DELETE FROM boss_agent_access WHERE agent_id = ?').bind(getTestAgentId()).run();
  await env.DB.prepare('UPDATE bosses SET archived_at = ? WHERE id = ?')
    .bind('2026-01-01T00:00:00.000Z', ADMIN).run();
  expect(await collectionList('agent')).toEqual([]);
  expect((await request(`?collection=${collection.id}`, 'GET', undefined, 'agent')).status).toBe(404);
});
