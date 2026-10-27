// Exercises share access and public capability behavior through real HTTP, D1 and R2.
// Uses Box fixtures and the additive share migration in the Workers test runtime.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import migration from '../../../migrations/0057_box_shares.sql?raw';
import { OWNER, OTHER, create, request, resetBox, seedBox, upload } from '../../box-test-helpers';
import { authHeaders } from '../../test-helpers';
import { hashApiKey } from '../../middleware/auth';
import { tokenHash } from './routes';
import { testJson } from '../../test-request';

const PEER = 'hb_test_share_peer';
const FOREIGN = 'hb_test_share_foreign';
type Share = { id: string; itemId: string; url: string; createdAt: string; expiresAt: string };
beforeAll(async () => {
  await seedBox();
  for (const sql of migration.replace(/^--.*$/gm, '').split(';').map(s => s.trim()).filter(Boolean)) {
    await env.DB.prepare(sql).run();
  }
});
beforeEach(async () => {
  await env.DB.prepare('DELETE FROM box_shares').run();
  await resetBox();
  for (const [id, key, boss] of [['share-peer', PEER, OWNER], ['share-foreign', FOREIGN, OTHER]]) {
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(id, id, await hashApiKey(key)).run();
    await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(boss, id).run();
  }
});

async function share(id: string, token = OWNER, body: unknown = {}): Promise<Share> {
  const response = await request(`/${id}/shares`, 'POST', body, token);
  expect(response.status).toBe(201);
  return response.json() as Promise<Share>;
}
function revoke(id: string, token = OWNER): Promise<Response> {
  const headers = token === 'agent' ? authHeaders() : { Authorization: `Bearer ${token}` };
  return SELF.fetch(`https://test.local/api/box/shares/${id}`, { method: 'DELETE', headers });
}
function headers(response: Response): void {
  expect(response.headers.get('cache-control')).toBe('private, no-store');
  expect(response.headers.get('x-robots-tag')).toBe('noindex, nofollow');
  expect(response.headers.get('referrer-policy')).toBe('no-referrer');
  expect(response.headers.get('x-content-type-options')).toBe('nosniff');
  expect(response.headers.get('content-security-policy')).toContain("default-src 'none'");
}

it('enforces boss, own-agent, other-agent and other-boss create/list access', async () => {
  const boss = await create({ text: 'boss' });
  const own = await create({ text: 'own', boss: OWNER }, 'agent');
  const peer = await create({ text: 'peer', boss: OWNER }, PEER);
  const foreign = await create({ text: 'foreign' }, OTHER);
  for (const item of [boss, own, peer]) {
    await share(item.id);
    expect((await request(`/${item.id}/shares`)).status).toBe(200);
  }
  await share(own.id, 'agent');
  expect((await request(`/${own.id}/shares`, 'GET', undefined, 'agent')).status).toBe(200);
  for (const [item, caller] of [[boss, 'agent'], [peer, 'agent'], [foreign, 'agent'],
    [foreign, OWNER], [own, OTHER]] as const) {
    expect((await request(`/${item.id}/shares`, 'POST', {}, caller)).status).toBe(404);
    expect((await request(`/${item.id}/shares`, 'GET', undefined, caller)).status).toBe(404);
  }
  await request(`/${own.id}`, 'DELETE', undefined, 'agent');
  expect((await request(`/${own.id}/shares`, 'POST', {}, 'agent')).status).toBe(404);
});

it('revokes only caller-owned shares, with boss override and idempotence', async () => {
  const item = await create({ text: 'own', boss: OWNER }, 'agent');
  const own = await share(item.id, 'agent');
  const boss = await share(item.id);
  const peerItem = await create({ text: 'peer', boss: OWNER }, PEER);
  const peer = await share(peerItem.id, PEER);
  for (const id of [boss.id, peer.id]) expect((await revoke(id, 'agent')).status).toBe(404);
  expect((await revoke(own.id, OTHER)).status).toBe(404);
  for (let n = 0; n < 2; n++) expect((await revoke(own.id, 'agent')).status).toBe(204);
  expect((await revoke(peer.id)).status).toBe(204);
  expect((await revoke(boss.id)).status).toBe(204);
  expect((await revoke('missing')).status).toBe(404);
});

it.each([3599, 2592001, '3600', null, false])('rejects invalid TTL %j', async ttlSeconds => {
  const item = await create({ text: 'ttl' });
  expect((await request(`/${item.id}/shares`, 'POST', { ttlSeconds })).status).toBe(400);
});

it('accepts TTL bounds/default and persists only a token hash', async () => {
  const item = await create({ text: 'ttl' });
  for (const ttl of [3600, 2592000, 604800]) {
    const result = await share(item.id, OWNER, ttl === 604800 ? {} : { ttlSeconds: ttl });
    expect(Date.parse(result.expiresAt) - Date.parse(result.createdAt)).toBe(ttl * 1000);
    const token = new URL(result.url).pathname.split('/').pop()!;
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const row = await env.DB.prepare('SELECT * FROM box_shares WHERE id = ?').bind(result.id).first();
    expect(row).toMatchObject({ token_hash: await tokenHash(token), created_by_agent: null });
    expect(JSON.stringify(row)).not.toContain(token);
    const listed = await (await request(`/${item.id}/shares`)).text();
    expect(listed).not.toContain(token);
    expect(listed).not.toContain('token_hash');
    expect(listed).not.toContain('url');
  }
});

it('returns identical public failures for unknown, expired, revoked, deleted and text file', async () => {
  const item = await create({ text: 'private' });
  const urls = ['https://test.local/s/unknown'];
  for (const mode of ['expired', 'revoked', 'file']) {
    const result = await share(item.id);
    if (mode === 'expired') await env.DB.prepare('UPDATE box_shares SET expires_at = ? WHERE id = ?')
      .bind('2000-01-01T00:00:00.000Z', result.id).run();
    if (mode === 'revoked') await revoke(result.id);
    urls.push(result.url + (mode === 'file' ? '/file' : ''));
  }
  const deleted = await create({ text: 'deleted' });
  const deletedShare = await share(deleted.id);
  await request(`/${deleted.id}`, 'DELETE');
  urls.push(deletedShare.url);
  const responses = [];
  for (const url of urls) {
    const response = await SELF.fetch(url);
    headers(response);
    expect(response.status).toBe(404);
    responses.push({ body: await response.text(), headers: Object.fromEntries(response.headers) });
  }
  for (const response of responses) expect(response).toEqual(responses[0]);
});

it('escapes title/text, rejects javascript href and counts only page GET', async () => {
  const item = await create({ text: '<script>alert(1)</script>', note: '<script>title</script>' });
  const result = await share(item.id);
  const page = await SELF.fetch(result.url);
  headers(page);
  const html = await page.text();
  expect(html).toContain('&lt;script&gt;');
  expect(html).not.toContain('<script>');
  await SELF.fetch(result.url, { method: 'HEAD' });
  await SELF.fetch(`${result.url}/file`);
  const row = await env.DB.prepare('SELECT view_count, last_viewed_at FROM box_shares WHERE id = ?')
    .bind(result.id).first<{ view_count: number; last_viewed_at: string }>();
  expect(row?.view_count).toBe(1);
  expect(row?.last_viewed_at).toBeTruthy();
  await env.DB.prepare("UPDATE box_items SET kind = 'link', url = ? WHERE id = ?")
    .bind('javascript:alert(1)', item.id).run();
  expect(await (await SELF.fetch(result.url)).text()).not.toContain('href="javascript:');
});

it.each(['image/svg+xml', 'text/html', 'image/png', 'application/pdf', 'image/heic', 'video/quicktime'])(
  'streams %s with share disposition, HEAD and ranges', async type => {
    const item = await (await upload(type)).json() as { id: string };
    const result = await share(item.id);
    const inline = !['image/svg+xml', 'text/html', 'application/pdf'].includes(type);
    for (const method of ['GET', 'HEAD']) {
      const response = await SELF.fetch(`${result.url}/file`, { method });
      expect(response.status).toBe(200);
      headers(response);
      expect(response.headers.get('content-security-policy'))
        .toBe("default-src 'none'; sandbox; frame-ancestors 'none'");
      expect(response.headers.get('content-type')).toBe(inline ? type : 'application/octet-stream');
      expect(response.headers.get('content-disposition')).toMatch(inline ? /^inline;/ : /^attachment;/);
      expect((await response.arrayBuffer()).byteLength).toBe(method === 'HEAD' ? 0 : 10);
    }
    const range = await SELF.fetch(`${result.url}/file`, { headers: { Range: 'bytes=1-3' } });
    expect(range.status).toBe(206);
    headers(range);
    expect((await range.arrayBuffer()).byteLength).toBe(3);
    const row = await env.DB.prepare('SELECT view_count FROM box_shares WHERE id = ?')
      .bind(result.id).first();
    expect(row).toEqual({ view_count: 0 });
  });

it('isolates authenticated peer agents and agents granted only to another boss', async () => {
  const first = await create({ text: 'first', boss: OWNER }, 'agent');
  const second = await create({ text: 'second', boss: OWNER }, PEER);
  const foreign = await create({ text: 'foreign', boss: OTHER }, FOREIGN);
  const bossItem = await create({ text: 'other boss' }, OTHER);
  const cases = [[first, 'agent'], [second, PEER], [foreign, FOREIGN], [bossItem, OTHER]] as const;
  for (const [item, caller] of cases) {
    const own = await share(item.id, caller);
    const listed = await request(`/${item.id}/shares`, 'GET', undefined, caller);
    expect(listed.status).toBe(200);
    expect(await listed.json()).toMatchObject({ shares: [{ id: own.id, active: true }] });
    const outsiders = caller === 'agent' ? [PEER, FOREIGN, OTHER]
      : caller === PEER ? ['agent', FOREIGN, OTHER]
      : caller === OTHER ? [OWNER, 'agent', PEER, FOREIGN] : [OWNER, 'agent', PEER];
    for (const outsider of outsiders) {
      expect((await request(`/${item.id}/shares`, 'POST', {}, outsider)).status).toBe(404);
      expect((await request(`/${item.id}/shares`, 'GET', undefined, outsider)).status).toBe(404);
      expect((await revoke(own.id, outsider)).status).toBe(404);
    }
    if (caller === FOREIGN) {
      const bossShare = await share(item.id, OTHER);
      const listedByBoss = await request(`/${item.id}/shares`, 'GET', undefined, OTHER);
      expect(listedByBoss.status).toBe(200);
      expect(await listedByBoss.json()).toMatchObject({
        shares: expect.arrayContaining([expect.objectContaining({ id: own.id, active: true })]),
      });
      expect((await revoke(own.id, OTHER)).status).toBe(204);
      expect((await revoke(bossShare.id, OTHER)).status).toBe(204);
    }
    expect((await revoke(own.id, caller)).status).toBe(204);
  }
  const ownerItem = await create({ text: 'owner' });
  const ownerShare = await share(ownerItem.id);
  for (const caller of [PEER, FOREIGN, OTHER]) {
    expect((await request(`/${ownerItem.id}/shares`, 'POST', {}, caller)).status).toBe(404);
    expect((await request(`/${ownerItem.id}/shares`, 'GET', undefined, caller)).status).toBe(404);
    expect((await revoke(ownerShare.id, caller)).status).toBe(404);
  }
});

it.each(['', '?purge=1'])('hides lists, pages and files after deletion %s', async query => {
  const item = await (await upload()).json() as { id: string };
  const result = await share(item.id);
  expect((await SELF.fetch(result.url)).status).toBe(200);
  expect((await SELF.fetch(`${result.url}/file`)).status).toBe(200);
  expect((await request(`/${item.id}${query}`, 'DELETE')).status).toBe(204);
  expect((await request(`/${item.id}/shares`)).status).toBe(404);
  expect((await SELF.fetch(result.url)).status).toBe(404);
  expect((await SELF.fetch(`${result.url}/file`)).status).toBe(404);
});

it.each([undefined, ''])('defaults TTL for absent or empty request body %j', async body => {
  const item = await create({ text: 'default ttl' });
  const result = await testJson(201, SELF.fetch(`https://test.local/api/box/items/${item.id}/shares`, {
    method: 'POST', headers: { Authorization: `Bearer ${OWNER}` }, body,
  })) as Share;
  expect(Date.parse(result.expiresAt) - Date.parse(result.createdAt)).toBe(604800000);
});

it('stops serving pages and files while the owning boss is archived', async () => {
  const item = await (await upload()).json() as { id: string };
  const result = await share(item.id);
  expect((await SELF.fetch(result.url)).status).toBe(200);
  expect((await SELF.fetch(`${result.url}/file`)).status).toBe(200);
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(OWNER).run();
  try {
    for (const url of [result.url, `${result.url}/file`]) {
      const response = await SELF.fetch(url);
      headers(response);
      expect(response.status, url).toBe(404);
    }
  } finally {
    await env.DB.prepare('UPDATE bosses SET archived_at = NULL WHERE id = ?').bind(OWNER).run();
  }
  expect((await SELF.fetch(result.url)).status).toBe(200);
});
