// Exercises Box ingestion, retries, ownership, edits and deletion through HTTP.
// Uses the actual Workers pool, D1 migration and private R2 storage.
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { ADMIN, OWNER, OTHER, create, page, request, seedBox, upload, type Item } from './box-test-helpers';
import { getTestAgentId } from './test-helpers';
import type { BoxRow } from './box/types';

beforeAll(seedBox);

it('creates JSON link and text items with owner identity and supplied metadata', async () => {
  const url = 'https://example.invalid/reference?verbatim=%2F';
  const link = await create({ url, text: 'title', note: 'use this', tags: ['layout'], source: 'mac-share' });
  expect(link).toMatchObject({ kind: 'link', url, text: 'title', boss_id: OWNER,
    boss_name: 'Box Owner', tags: ['layout'], has_media: false, source: 'mac-share' });
  expect(link.id).toMatch(/^bx_[a-f0-9]+$/);
  const text = await create({ text: 'a passage', project: 'design', source: 'cli' });
  expect(text).toMatchObject({ kind: 'text', text: 'a passage', project: 'design', url: null });
});

it('creates private multipart media and serves correctly ranged bytes', async () => {
  const response = await upload('image/png', 10, { width: 2, height: 5, note: 'caption' });
  expect(response.status).toBe(201);
  const item = await response.json() as Item;
  expect(item).toMatchObject({ kind: 'image', media_bytes: 10, media_type: 'image/png',
    width: 2, height: 5, boss_id: OWNER, boss_name: 'Box Owner', has_media: true });
  expect(item).not.toHaveProperty('media_key');
  expect(item).not.toHaveProperty('deleted_at');
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${item.id}`)).not.toBeNull();
  const media = await request(`/${item.id}/media`, 'GET', undefined, 'agent', { Range: 'bytes=2-5' });
  expect(media.status).toBe(206);
  expect(media.headers.get('Content-Range')).toBe('bytes 2-5/10');
  expect(media.headers.get('Cache-Control')).toBe('private, no-store');
  expect(await media.text()).toBe('AAAA');
  const head = await request(`/${item.id}/media`, 'HEAD');
  expect(head.status).toBe(200);
  expect(head.headers.get('Content-Length')).toBe('10');
  expect(await head.text()).toBe('');
});

it('keeps every public field across item responses and replaces storage fields with has_media', async () => {
  for (const media of [false, true]) {
    const key = `response-${media}`;
    const meta = { text: 'responseneedle', project: key, tags: ['reference'], note: 'caption' };
    const created = media ? await upload('image/png', 3, meta, OWNER, key)
      : await request('', 'POST', meta, OWNER, { 'Idempotency-Key': key });
    expect(created.status).toBe(201);
    const item = await created.json() as Item;
    const row = await env.DB.prepare(`SELECT i.*, b.name AS boss_name FROM box_items i
      JOIN bosses b ON b.id = i.boss_id WHERE i.id = ?`).bind(item.id).first<BoxRow>();
    expect(row).not.toBeNull();
    if (!row) throw new Error('created item missing');
    const { media_key, deleted_at, ...stored } = row;
    const expected = { ...stored, tags: ['reference'], has_media: media };
    expect(item).toEqual(expected);
    const replay = await request('', 'POST', { text: 'ignored' }, OWNER, { 'Idempotency-Key': key });
    expect(replay.status).toBe(201);
    expect(await replay.json()).toEqual(expected);
    for (const path of [`/${item.id}`, `/latest?project=${key}`]) {
      const response = await request(path);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual(expected);
    }
    for (const path of [`?project=${key}`, `/search?q=responseneedle&project=${key}`]) {
      expect((await page(path)).items).toEqual([expected]);
    }
    const patched = await request(`/${item.id}`, 'PATCH', { note: 'edited' });
    expect(patched.status).toBe(200);
    expect(await patched.json()).toEqual({ ...expected, note: 'edited' });
  }
});

it.each(['text', 'note'])('enforces the 16 KB %s byte limit with 413', async field => {
  expect((await request('', 'POST', { text: 'valid', [field]: 'é'.repeat(8193) })).status).toBe(413);
  expect((await request('', 'POST', { text: 'valid', [field]: 'é'.repeat(8192) })).status).toBe(201);
  expect((await upload('image/png', 1, { [field]: 'x'.repeat(16385) })).status).toBe(413);
});

it.each([{ type: 'image/png', megabytes: 10 }, { type: 'video/mp4', megabytes: 50 },
  { type: 'application/pdf', megabytes: 50 }])(
  'enforces the $type media limit with 413', async ({ type, megabytes }) => {
    const response = await upload(type, megabytes * 1024 * 1024 + 1);
    expect(response.status).toBe(413);
  });

it.each([['video/mp4', 'video'], ['application/pdf', 'file']])(
  'derives the %s upload kind', async (type, kind) => {
    const response = await upload(type, 4, { duration_ms: 123 });
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ kind, duration_ms: 123 });
  });

it('deduplicates JSON retries atomically and scopes keys to the boss', async () => {
  const key = 'same-key';
  const replies = await Promise.all(Array.from({ length: 2 }, () => request('', 'POST',
    { text: 'retry' }, OWNER, { 'Idempotency-Key': key })));
  expect(replies.map(reply => reply.status)).toEqual([201, 201]);
  const items = await Promise.all(replies.map(reply => reply.json() as Promise<Item>));
  expect(items[0].id).toBe(items[1].id);
  const count = await env.DB.prepare(`SELECT COUNT(*) AS n FROM box_items
    WHERE boss_id = ? AND text = 'retry'`)
    .bind(OWNER).first<{ n: number }>();
  expect(count?.n).toBe(1);
  const other = await request('', 'POST', { text: 'other retry' }, OTHER, { 'Idempotency-Key': key });
  expect(other.status).toBe(201);
  expect((await other.json() as Item).id).not.toBe(items[0].id);
});

it('deduplicates multipart retries without orphaning objects', async () => {
  const responses = await Promise.all([upload('image/png', 5, {}, OWNER, 'media-retry'),
    upload('image/png', 5, {}, OWNER, 'media-retry')]);
  expect(responses.map(response => response.status)).toEqual([201, 201]);
  const items = await Promise.all(responses.map(response => response.json() as Promise<Item>));
  expect(items[0].id).toBe(items[1].id);
  const rows = await env.DB.prepare("SELECT media_key FROM box_items WHERE id = ?")
    .bind(items[0].id).all<{ media_key: string }>();
  expect(rows.results).toHaveLength(1);
  const objects = await env.ATTACHMENTS.list({ prefix: `box/${OWNER}/` });
  const stored = await env.DB.prepare(`SELECT media_key FROM box_items
    WHERE boss_id = ? AND media_key IS NOT NULL`).bind(OWNER).all<{ media_key: string }>();
  expect(objects.objects.map(object => object.key).sort())
    .toEqual(stored.results.map(row => row.media_key).sort());
});

it('reuses panel grants and admin access for reads, including cross-boss identity', async () => {
  const item = await create({ text: 'permissionneedle' });
  const adminItem = await create({ text: 'adminneedle' }, ADMIN);
  expect((await request(`/${item.id}`, 'GET', undefined, 'agent')).status).toBe(200);
  const list = await page('?boss=Box%20Owner', 'agent');
  expect(list.items.some(row => row.id === item.id)).toBe(true);
  expect(list.items.every(row => row.boss_id === OWNER && row.boss_name === 'Box Owner')).toBe(true);
  expect((await request('/latest?boss=box-owner', 'GET', undefined, 'agent')).status).toBe(200);
  expect((await page('/search?q=permissionneedle', 'agent')).items[0].id).toBe(item.id);
  expect((await page('?boss=box-admin', 'agent')).items[0].id).toBe(adminItem.id);
  expect((await page('', ADMIN)).items.every(row => row.boss_id === ADMIN)).toBe(true);
});

it('returns 404 on every read without access and after an explicit grant is revoked', async () => {
  const image = await (await upload('image/png', 3, { text: 'hiddenneedle' }, OTHER)).json() as Item;
  const paths = ['?boss=box-other', '/latest?boss=box-other', '/search?q=hiddenneedle&boss=box-other',
    `/${image.id}`, `/${image.id}/media`];
  for (const path of paths) expect((await request(path, 'GET', undefined, 'agent')).status).toBe(404);
  for (const path of [`/${image.id}`, `/${image.id}/media`]) {
    expect((await request(path)).status).toBe(404);
  }
  expect((await page('', 'agent')).items.some(item => item.id === image.id)).toBe(false);
  expect((await page('/search?q=hiddenneedle', 'agent')).items).toEqual([]);
  await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ? AND agent_id = ?')
    .bind(OWNER, getTestAgentId()).run();
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(ADMIN).run();
  for (const path of ['', '/latest', '/search?q=hiddenneedle', `/${image.id}`, `/${image.id}/media`]) {
    expect((await request(path, 'GET', undefined, 'agent')).status).toBe(404);
  }
});

it('blocks agent creation, patching and deletion, and boss writes to another box', async () => {
  const item = await create({ text: 'immutable' });
  for (const [path, method] of [['', 'POST'], [`/${item.id}`, 'PATCH'], [`/${item.id}`, 'DELETE']]) {
    expect((await request(path, method, { text: 'blocked', note: 'blocked' }, 'agent')).status).toBe(404);
  }
  for (const method of ['PATCH', 'DELETE']) {
    expect((await request(`/${item.id}`, method, { note: 'blocked' }, OTHER)).status).toBe(404);
  }
  expect(await (await request(`/${item.id}`)).json()).toMatchObject({ text: 'immutable', note: null });
});

it('updates only note, project and tags, keeping FTS synchronized', async () => {
  const item = await create({ text: 'editable', note: 'oldneedle', tags: ['oldtag'] });
  const edited = await request(`/${item.id}`, 'PATCH', {
    note: 'newneedle', project: 'new', tags: ['newtag'],
  });
  expect(edited.status).toBe(200);
  expect(await edited.json()).toMatchObject({ boss_id: OWNER, boss_name: 'Box Owner',
    note: 'newneedle', project: 'new', tags: ['newtag'] });
  expect((await page('/search?q=oldneedle')).items).toEqual([]);
  expect((await page('/search?q=newtag&project=new')).items[0].id).toBe(item.id);
  expect((await request(`/${item.id}`, 'PATCH', { note: 'x'.repeat(16385) })).status).toBe(413);
  expect((await request(`/${item.id}`, 'PATCH', { text: 'forbidden' })).status).toBe(400);
});

it('hides soft-deleted items everywhere and purges the row and private object', async () => {
  const response = await upload('image/png', 6, { text: 'deletionneedle' }, OWNER, 'delete-retry');
  const item = await response.json() as Item;
  expect((await request(`/${item.id}`, 'DELETE')).status).toBe(204);
  for (const path of [`/${item.id}`, `/${item.id}/media`]) expect((await request(path)).status).toBe(404);
  expect((await page('')).items.some(row => row.id === item.id)).toBe(false);
  expect((await page('/search?q=deletionneedle')).items).toEqual([]);
  const latest = await request('/latest?kind=image');
  if (latest.status === 200) expect((await latest.json() as Item).id).not.toBe(item.id);
  else expect(latest.status).toBe(404);
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${item.id}`)).not.toBeNull();
  expect((await request(`/${item.id}?purge=1`, 'DELETE')).status).toBe(204);
  expect(await env.DB.prepare('SELECT id FROM box_items WHERE id = ?').bind(item.id).first()).toBeNull();
  expect(await env.ATTACHMENTS.head(`box/${OWNER}/${item.id}`)).toBeNull();
  expect((await upload('image/png', 6, {}, OWNER, 'delete-retry')).status).toBe(404);
});

it('rejects malformed metadata, cursors and filters without changing data', async () => {
  for (const body of [{}, [], { text: 1 }, { text: 'ok', tags: [1] }, { text: 'ok', source: 'unknown' }]) {
    expect((await request('', 'POST', body)).status).toBe(400);
  }
  for (const query of ['?kind=unknown', '?limit=0', '?limit=1.5', '?since=bad', '?cursor=bad']) {
    expect((await request(query)).status).toBe(400);
  }
  expect((await request('/search?q=')).status).toBe(400);
});

it.each([
  { url: 'é'.repeat(4097) },
  { project: 'x'.repeat(129) },
  { tags: Array.from({ length: 21 }, () => 'tag') },
  { tags: ['x'.repeat(65)] },
])('rejects oversized JSON metadata with 400: %j', async body => {
  expect((await request('', 'POST', { text: 'valid', ...body })).status).toBe(400);
  const item = await create({ text: 'unchanged' });
  expect((await request(`/${item.id}`, 'PATCH', body)).status).toBe(400);
  expect(await (await request(`/${item.id}`)).json())
    .toMatchObject({ text: 'unchanged', project: null, tags: [] });
});

it('accepts JSON metadata at its URL, project and tag limits', async () => {
  const body = { url: 'é'.repeat(4096), project: 'x'.repeat(128),
    tags: Array.from({ length: 20 }, () => 'x'.repeat(64)) };
  const item = await create(body);
  expect(item).toMatchObject(body);
  const patched = await request(`/${item.id}`, 'PATCH', { project: body.project, tags: body.tags });
  expect(patched.status).toBe(200);
  expect(await patched.json()).toMatchObject(body);
});
