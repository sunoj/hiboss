// Verifies Box recency filters and ranked FTS search over every indexed field.
// Uses real HTTP routes, shared grants, D1 triggers and stable cursor pagination.
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { OWNER, OTHER, create, page, request, seedBox, type Item } from './box-test-helpers';

beforeAll(seedBox);

async function dated(text: string, createdAt: string, project = 'filter', token = OWNER): Promise<Item> {
  const item = await create({ text, project }, token);
  await env.DB.prepare('UPDATE box_items SET created_at = ? WHERE id = ?').bind(createdAt, item.id).run();
  return { ...item, created_at: createdAt };
}

it('filters lists by kind, since, project and boss with stable recency cursors', async () => {
  const first = await dated('old', '2024-01-01T00:00:00.000Z');
  const second = await dated('middle', '2024-01-02T00:00:00.000Z');
  const third = await dated('new', '2024-01-03T00:00:00.000Z');
  await create({ url: 'https://example.invalid/filter', project: 'filter' });
  await create({ text: 'another project', project: 'other' });
  await dated('inaccessible', '2024-01-04T00:00:00.000Z', 'filter', OTHER);
  const query = '?kind=text&project=filter&boss=Box%20Owner&since=2024-01-02T00:00:00Z&limit=1';
  const one = await page(query, 'agent');
  expect(one.items.map(item => item.id)).toEqual([third.id]);
  expect(one.next_cursor).toMatch(/^[A-Za-z0-9_-]+$/);
  const two = await page(`${query}&cursor=${one.next_cursor}`, 'agent');
  expect(two.items.map(item => item.id)).toEqual([second.id]);
  expect(two.next_cursor).toBeNull();
  const all = await page('?kind=text&project=filter');
  expect(all.items.map(item => item.id)).toEqual([third.id, second.id, first.id]);
  const recent = await create({ text: 'relative', project: 'relative' });
  expect((await page('?since=1h&project=relative')).items[0].id).toBe(recent.id);
});

it('breaks equal timestamp ties by id and caps list limits at 100', async () => {
  const date = '2024-01-01T00:00:00.000Z';
  const items = await Promise.all(['one', 'two', 'three'].map(text => dated(text, date, 'ties')));
  const sorted = items.map(item => item.id).sort().reverse();
  const first = await page('?project=ties&limit=2');
  expect(first.items.map(item => item.id)).toEqual(sorted.slice(0, 2));
  const second = await page(`?project=ties&limit=2&cursor=${first.next_cursor}`);
  expect(second.items.map(item => item.id)).toEqual(sorted.slice(2));
  expect(second.next_cursor).toBeNull();
  const many = Array.from({ length: 102 }, (_, n) => env.DB.prepare(`INSERT INTO box_items
    (id, boss_id, kind, text, source, created_at) VALUES (?, ?, 'text', 'cap', 'cli', ?)`)
    .bind(`bx_limit_${n}`, OWNER, date));
  await env.DB.batch(many);
  expect((await page('?limit=200')).items).toHaveLength(100);
});

it('returns the newest matching item and 404 for an empty latest result', async () => {
  const text = await create({ text: 'new text' });
  const link = await create({ url: 'https://example.invalid/latest' });
  const latest = await request('/latest?kind=text', 'GET', undefined, 'agent');
  expect(await latest.json()).toMatchObject({ id: text.id, boss_id: OWNER, boss_name: 'Box Owner' });
  expect(await (await request('/latest?kind=link')).json()).toMatchObject({ id: link.id });
  expect((await request('/latest?kind=video')).status).toBe(404);
});

it('rejects raw JSON, malformed base64url and invalid cursor payloads', async () => {
  const raw = JSON.stringify({ created_at: '2024-01-01T00:00:00.000Z', id: 'bx_cursor' });
  const encoded = btoa(raw).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  const invalid = ['', raw, `${encoded}=`, `${encoded}+`, 'a', btoa('not json'),
    btoa('{}'), btoa(JSON.stringify({ created_at: 'bad', id: 'bx_cursor' })),
    btoa(JSON.stringify({ created_at: '2024-01-01T00:00:00.000Z', id: '', score: 'bad' }))];
  for (const value of invalid) {
    for (const path of ['', '/search?q=needle']) {
      expect((await request(`${path}${path ? '&' : '?'}cursor=${encodeURIComponent(value)}`)).status)
        .toBe(400);
    }
  }
  expect((await request(`/search?q=needle&cursor=${encoded}`)).status).toBe(400);
});

it('ranks FTS matches and applies every list filter before ranked pagination', async () => {
  const best = await dated('rankingneedle rankingneedle rankingneedle', '2024-01-02T00:00:00.000Z');
  const weak = await dated('rankingneedle with many additional words diluting this match',
    '2024-01-03T00:00:00.000Z');
  await dated('rankingneedle', '2023-01-01T00:00:00.000Z');
  await create({ url: 'https://example.invalid/rankingneedle', project: 'filter' });
  await create({ text: 'rankingneedle', project: 'elsewhere' });
  await create({ text: 'rankingneedle', project: 'filter' }, OTHER);
  const query = '/search?q=rankingneedle&kind=text&project=filter&boss=box-owner'
    + '&since=2024-01-01T00:00:00Z&limit=1';
  const first = await page(query, 'agent');
  expect(first.items.map(item => item.id)).toEqual([best.id]);
  expect(first.next_cursor).toMatch(/^[A-Za-z0-9_-]+$/);
  const cursor = first.next_cursor;
  const second = await page(`${query}&cursor=${cursor}`, 'agent');
  expect(second.items.map(item => item.id)).toEqual([weak.id]);
  expect(second.next_cursor).toBeNull();
  expect(second.items[0]).toMatchObject({ boss_id: OWNER, boss_name: 'Box Owner' });
});

it('searches text, note, URL and tags and treats query terms as literal FTS tokens', async () => {
  const text = await create({ text: 'textneedle' });
  const note = await create({ text: 'caption', note: 'noteneedle' });
  const url = await create({ url: 'https://example.invalid/urlneedle' });
  const tag = await create({ text: 'tagged', tags: ['tagneedle'] });
  for (const [query, item] of [['textneedle', text], ['noteneedle', note],
    ['urlneedle', url], ['tagneedle', tag]] as const) {
    expect((await page(`/search?q=${query}`)).items.map(row => row.id)).toEqual([item.id]);
  }
  const tokens = await create({ text: 'term OR other' });
  expect((await page('/search?q=term%20OR%20other')).items.map(row => row.id)).toEqual([tokens.id]);
  expect((await request('/search?q=%22')).status).toBe(200);
});

it('paginates equal-ranked results without repeats and hides deleted search entries', async () => {
  const date = '2024-01-01T00:00:00.000Z';
  const items = await Promise.all([dated('tieneedle', date), dated('tieneedle', date)]);
  const sorted = items.map(item => item.id).sort().reverse();
  const first = await page('/search?q=tieneedle&limit=1');
  expect(first.items[0].id).toBe(sorted[0]);
  const next = await page('/search?q=tieneedle&limit=1&cursor='
    + first.next_cursor);
  expect(next.items[0].id).toBe(sorted[1]);
  expect(next.next_cursor).toBeNull();
  expect((await request(`/${sorted[0]}`, 'DELETE')).status).toBe(204);
  expect((await page('/search?q=tieneedle')).items.map(row => row.id)).toEqual([sorted[1]]);
  expect((await request(`/${sorted[1]}?purge=1`, 'DELETE')).status).toBe(204);
  expect((await page('/search?q=tieneedle')).items).toEqual([]);
  const index = await env.DB.prepare('SELECT rowid FROM box_items_fts WHERE box_items_fts MATCH ?')
    .bind('tieneedle').all();
  expect(index.results).toEqual([]);
});
