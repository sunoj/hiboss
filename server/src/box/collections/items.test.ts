// Verifies likes, item response metadata and membership deletion lifecycle.
// Uses existing HTTP/D1/R2 Box helpers and collection route helpers.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import { OTHER, create, page, request, resetBox, seedBox, upload, type Item } from '../../box-test-helpers';
import { collectionList, collections, membership, newCollection } from './test-helpers';

beforeAll(seedBox);
beforeEach(() => resetBox());

it('likes and unlikes idempotently while preserving the original like timestamp', async () => {
  const item = await create({ text: 'like me' });
  expect(item).toMatchObject({ liked: false, liked_at: null, collection_ids: [] });
  const first = await request(`/${item.id}/like`, 'PUT');
  expect(first.status).toBe(200);
  const liked = await first.json() as Item;
  expect(liked.liked).toBe(true);
  expect(Number.isFinite(Date.parse(liked.liked_at!))).toBe(true);
  await env.DB.prepare('UPDATE box_items SET liked_at = ? WHERE id = ?')
    .bind('2020-01-01T00:00:00.000Z', item.id).run();
  const repeated = await request(`/${item.id}/like`, 'PUT');
  expect(repeated.status).toBe(200);
  expect(await repeated.json()).toMatchObject({ liked_at: '2020-01-01T00:00:00.000Z' });
  for (let n = 0; n < 2; n++) {
    const response = await request(`/${item.id}/like`, 'DELETE');
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ liked: false, liked_at: null });
  }
});

it('hides like writes from agents, other bosses, missing IDs and soft-deleted items', async () => {
  const boss = await create({ text: 'boss' });
  const agent = await create({ text: 'agent', boss: boss.boss_id }, 'agent');
  for (const method of ['PUT', 'DELETE']) {
    for (const item of [boss, agent]) {
      expect((await request(`/${item.id}/like`, method, undefined, 'agent')).status).toBe(404);
      expect((await request(`/${item.id}/like`, method, undefined, OTHER)).status).toBe(404);
    }
    expect((await request('/bx_missing/like', method)).status).toBe(404);
  }
  await request(`/${boss.id}`, 'DELETE');
  for (const method of ['PUT', 'DELETE']) {
    expect((await request(`/${boss.id}/like`, method)).status).toBe(404);
  }
});

it('returns likes and memberships in show, latest, list, search, patch and create replay', async () => {
  const response = await request('', 'POST', { text: 'metadataneedle' }, undefined,
    { 'Idempotency-Key': 'collection-response' });
  expect(response.status).toBe(201);
  const item = await response.json() as Item;
  const collection = await newCollection('Metadata');
  await request(`/${item.id}/like`, 'PUT');
  const expected = await membership(collection.id, item.id);
  expect(expected).toMatchObject({ liked: true, collection_ids: [collection.id] });
  for (const path of [`/${item.id}`, '/latest']) {
    const read = await request(path, 'GET', undefined, 'agent');
    expect(await read.json()).toEqual(expected);
  }
  for (const path of ['', '/search?q=metadataneedle']) {
    expect((await page(path, 'agent')).items).toEqual([expected]);
  }
  const patch = await request(`/${item.id}`, 'PATCH', { note: 'updated' });
  expect(await patch.json()).toEqual({ ...expected, note: 'updated' });
  const replay = await request('', 'POST', { text: 'ignored' }, undefined,
    { 'Idempotency-Key': 'collection-response' });
  expect(await replay.json()).toEqual({ ...expected, note: 'updated' });
});

it('hides soft-deleted members from counts, covers and lists, and purges membership rows', async () => {
  const collection = await newCollection('Lifecycle');
  const text = await create({ text: 'lifecycleneedle' });
  const image = await (await upload()).json() as Item;
  const video = await (await upload('video/mp4')).json() as Item;
  const newer = await create({ text: 'newest text' });
  for (const [index, item] of [text, image, video, newer].entries()) {
    await env.DB.prepare('UPDATE box_items SET created_at = ? WHERE id = ?')
      .bind(`2026-01-0${index + 1}T00:00:00.000Z`, item.id).run();
    await membership(collection.id, item.id);
    await request(`/${item.id}/like`, 'PUT');
  }
  expect((await collectionList())[0]).toMatchObject({ item_count: 4, cover_item_id: video.id });
  await request(`/${video.id}`, 'DELETE');
  expect((await collectionList())[0]).toMatchObject({ item_count: 3, cover_item_id: image.id });
  const filter = `?collection=${collection.id}&liked=1`;
  expect((await page(filter)).items.map(row => row.id)).toEqual([newer.id, image.id, text.id]);
  expect(await env.DB.prepare('SELECT item_id FROM box_collection_items WHERE item_id = ?')
    .bind(video.id).first()).toEqual({ item_id: video.id });
  expect((await collections(`/${collection.id}/items/${video.id}`, 'DELETE')).status).toBe(404);
  expect((await request(`/${video.id}?purge=1`, 'DELETE')).status).toBe(204);
  expect(await env.DB.prepare('SELECT item_id FROM box_collection_items WHERE item_id = ?')
    .bind(video.id).first()).toBeNull();
  for (const item of [image, text, newer]) await request(`/${item.id}`, 'DELETE');
  expect((await collectionList())[0]).toMatchObject({ item_count: 0, cover_item_id: null });
  expect((await page(filter)).items).toEqual([]);
  expect((await page(`/search?q=lifecycleneedle&collection=${collection.id}&liked=1`)).items).toEqual([]);
  expect((await request(`/latest${filter}`)).status).toBe(404);
  expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM box_collection_items').first())
    .toEqual({ count: 3 });
  expect((await request(`/${text.id}?purge=1`, 'DELETE')).status).toBe(204);
  expect(await env.DB.prepare('SELECT item_id FROM box_collection_items WHERE item_id = ?')
    .bind(text.id).first()).toBeNull();
});

it('purges live items from every collection without deleting collections or other items', async () => {
  const a = await newCollection('One');
  const b = await newCollection('Two');
  const purged = await create({ text: 'purge live' });
  const kept = await create({ text: 'keep live' });
  await membership(a.id, purged.id);
  await membership(b.id, purged.id);
  await membership(a.id, kept.id);
  expect((await request(`/${purged.id}?purge=1`, 'DELETE')).status).toBe(204);
  expect(await env.DB.prepare('SELECT item_id FROM box_collection_items WHERE item_id = ?')
    .bind(purged.id).all()).toMatchObject({ results: [] });
  expect((await collectionList()).map(row => [row.id, row.item_count, row.cover_item_id]))
    .toEqual([[a.id, 1, null], [b.id, 0, null]]);
  expect(await (await request(`/${kept.id}`)).json()).toMatchObject({ collection_ids: [a.id] });
});
