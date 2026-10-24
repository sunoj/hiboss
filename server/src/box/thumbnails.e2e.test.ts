// Exercises Box thumbnail upload, replacement, serving and cleanup through real HTTP.
// Uses the Workers pool with D1 migrations through 0062 and private R2 storage.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, expect, it } from 'vitest';
import { OWNER, create, request, resetBox, seedBox, type Item } from '../box-test-helpers';
import { authHeaders, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const PEER = 'synthetic-thumb-peer-key';
const PEER_ID = 'box-thumb-peer-agent';
const JPEG = [0xff, 0xd8, 0xff, 0xe0];
const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const WEBP = [0x52, 0x49, 0x46, 0x46, 1, 0, 0, 0, 0x57, 0x45, 0x42, 0x50];

beforeAll(async () => {
  await seedBox();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(PEER_ID, 'Thumb Peer', await hashApiKey(PEER)).run();
});
beforeEach(() => resetBox([getTestAgentId(), PEER_ID]));
afterEach(() => resetBox([getTestAgentId(), PEER_ID]));

function image(magic: number[], size = 64): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(size).fill(7);
  bytes.set(magic);
  return bytes;
}

function bearer(token: string): string {
  return token === 'agent' ? authHeaders().Authorization : `Bearer ${token}`;
}

function post(type: string, thumb: { type: string; bytes: Uint8Array<ArrayBuffer> } | null,
  token = OWNER): Promise<Response> {
  const form = new FormData();
  form.set('meta', JSON.stringify({ source: 'ios-share' }));
  form.set('file', new File([image(PNG, 32)], 'original', { type }));
  if (thumb) form.set('thumbnail', new File([thumb.bytes], 'thumb', { type: thumb.type }));
  return SELF.fetch('https://test.local/api/box/items', {
    method: 'POST', headers: { Authorization: bearer(token) }, body: form,
  });
}

function put(id: string, type: string, bytes: Uint8Array<ArrayBuffer>, token = OWNER): Promise<Response> {
  return SELF.fetch(`https://test.local/api/box/items/${id}/thumbnail`, {
    method: 'PUT', headers: { Authorization: bearer(token), 'Content-Type': type }, body: bytes,
  });
}

async function media(type = 'image/png', token = OWNER): Promise<Item> {
  const response = await post(type, null, token);
  expect(response.status, await response.clone().text()).toBe(201);
  return response.json() as Promise<Item>;
}

async function objectKeys(): Promise<string[]> {
  return (await env.ATTACHMENTS.list({ prefix: 'box/' })).objects.map(object => object.key).sort();
}

it('creates an item with a thumbnail part and serves it with private cache headers', async () => {
  const thumb = image(JPEG, 100);
  const response = await post('image/png', { type: 'image/jpeg', bytes: thumb });
  expect(response.status, await response.clone().text()).toBe(201);
  const item = await response.json() as Item;
  expect(item).toMatchObject({ kind: 'image', has_media: true, has_thumbnail: true });
  expect(item).not.toHaveProperty('thumb_key');
  expect(item).not.toHaveProperty('thumb_bytes');
  expect(await objectKeys()).toEqual([`box/${OWNER}/${item.id}`, `box/${OWNER}/${item.id}.thumb`]);
  const got = await request(`/${item.id}/thumbnail`, 'GET', undefined, 'agent');
  expect(got.status).toBe(200);
  expect(got.headers.get('content-type')).toBe('image/jpeg');
  expect(got.headers.get('x-content-type-options')).toBe('nosniff');
  expect(got.headers.get('cache-control')).toBe('private, max-age=86400');
  const etag = got.headers.get('etag');
  expect(etag).toBeTruthy();
  expect(new Uint8Array(await got.arrayBuffer())).toEqual(thumb);
  const head = await request(`/${item.id}/thumbnail`, 'HEAD');
  expect(head.status).toBe(200);
  expect(head.headers.get('content-length')).toBe('100');
  expect(head.headers.get('etag')).toBe(etag);
  expect(await head.text()).toBe('');
  const cached = await request(`/${item.id}/thumbnail`, 'GET', undefined, OWNER,
    { 'If-None-Match': etag ?? '' });
  expect(cached.status).toBe(304);
});

it('replaces a thumbnail with PUT and returns the item JSON', async () => {
  const item = await media('video/mp4');
  expect(item.has_thumbnail).toBe(false);
  expect((await request(`/${item.id}/thumbnail`)).status).toBe(404);
  for (const [type, bytes] of [['image/png', image(PNG)], ['image/webp; q=1', image(WEBP, 90)]] as const) {
    const response = await put(item.id, type, bytes);
    expect(response.status, await response.clone().text()).toBe(200);
    const body = await response.json() as Item;
    expect(body).toMatchObject({ id: item.id, kind: 'video', has_thumbnail: true });
    expect(body).not.toHaveProperty('thumb_key');
    const got = await request(`/${item.id}/thumbnail`);
    expect(got.headers.get('content-type')).toBe(type.split(';')[0]);
    expect(new Uint8Array(await got.arrayBuffer())).toEqual(bytes);
  }
  const listed = await request(`?kind=video`);
  expect(JSON.stringify(await listed.json())).not.toMatch(/thumb_key|thumb_bytes/);
  const shown = await request(`/${item.id}`);
  expect(await shown.json()).toMatchObject({ has_thumbnail: true });
});

it.each([
  ['image/gif', image([0x47, 0x49, 0x46, 0x38])],
  ['image/jpeg', image(PNG)],
  ['image/png', image(JPEG)],
  ['image/webp', image([0x52, 0x49, 0x46, 0x46, 1, 0, 0, 0, 0x41, 0x56, 0x49, 0x20])],
  ['text/plain', image(JPEG)],
])('rejects %s thumbnails whose type or magic is wrong with 415', async (type, bytes) => {
  const item = await media();
  expect((await put(item.id, type, bytes)).status).toBe(415);
  const before = await objectKeys();
  expect((await post('image/png', { type, bytes })).status).toBe(415);
  expect(await objectKeys()).toEqual(before);
  const listed = await request('?kind=image').then(async r => r.json() as Promise<{ items: Item[] }>);
  expect(listed.items).toHaveLength(1);
});

it('rejects thumbnails over 256 KiB with 413 and stores nothing', async () => {
  const item = await media();
  const limit = image(JPEG, 256 * 1024);
  expect((await put(item.id, 'image/jpeg', limit)).status).toBe(200);
  const oversized = image(JPEG, 256 * 1024 + 1);
  expect((await put(item.id, 'image/jpeg', oversized)).status).toBe(413);
  const stored = await env.ATTACHMENTS.head(`box/${OWNER}/${item.id}.thumb`);
  expect(stored?.size).toBe(256 * 1024);
  const keys = await objectKeys();
  expect((await post('image/png', { type: 'image/jpeg', bytes: oversized })).status).toBe(413);
  expect(await objectKeys()).toEqual(keys);
});

it('rejects thumbnails for items without image or video media with 409', async () => {
  const text = await create({ text: 'no media' });
  expect((await put(text.id, 'image/jpeg', image(JPEG))).status).toBe(409);
  const file = await media('application/pdf');
  expect((await put(file.id, 'image/jpeg', image(JPEG))).status).toBe(409);
  expect((await post('application/pdf', { type: 'image/jpeg', bytes: image(JPEG) })).status).toBe(409);
  expect(await objectKeys()).toEqual([`box/${OWNER}/${file.id}`]);
});

it('lets an agent PUT only on its own items; other authors read 404', async () => {
  const boss = await media();
  expect((await put(boss.id, 'image/jpeg', image(JPEG), 'agent')).status).toBe(404);
  const peer = await media('image/png', PEER);
  expect((await put(peer.id, 'image/jpeg', image(JPEG), 'agent')).status).toBe(404);
  expect((await put(peer.id, 'image/jpeg', image(JPEG), PEER)).status).toBe(200);
  expect((await put(peer.id, 'image/jpeg', image(JPEG), OWNER)).status).toBe(200);
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${boss.id}.thumb`)).toBeNull();
  expect((await request(`/${peer.id}/thumbnail`, 'GET', undefined, 'agent')).status).toBe(200);
});

it('keeps the thumbnail on soft delete and removes it from R2 on purge', async () => {
  const response = await post('image/png', { type: 'image/jpeg', bytes: image(JPEG) });
  const item = await response.json() as Item;
  const key = `box/${OWNER}/${item.id}.thumb`;
  expect((await request(`/${item.id}`, 'DELETE')).status).toBe(204);
  expect(await env.ATTACHMENTS.head(key)).not.toBeNull();
  expect((await request(`/${item.id}/thumbnail`)).status).toBe(404);
  expect((await request(`/${item.id}?purge=1`, 'DELETE')).status).toBe(204);
  expect(await env.ATTACHMENTS.head(key)).toBeNull();
  expect(await objectKeys()).toEqual([]);
});
