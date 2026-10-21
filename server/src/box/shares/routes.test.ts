// Exercises share access and public capability behavior through real HTTP, D1 and R2.
// Uses Box fixtures and the additive share migration in the Workers test runtime.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import migration from '../../../migrations/0057_box_shares.sql?raw';
import { OWNER, OTHER, create, request, resetBox, seedBox, upload } from '../../box-test-helpers';
import { authHeaders } from '../../test-helpers';
import { tokenHash } from './routes';

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
  const peer = await create({ text: 'peer' });
  const foreign = await create({ text: 'foreign' }, OTHER);
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('peer-id', 'Peer', 'synthetic-share-peer-hash').run();
  await env.DB.prepare('UPDATE box_items SET agent_id = ? WHERE id = ?')
    .bind('peer-id', peer.id).run();
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
  const peer = await share(item.id);
  await env.DB.prepare('UPDATE box_shares SET created_by_agent = ? WHERE id = ?')
    .bind('peer-id', peer.id).run();
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
    const inline = !['image/svg+xml', 'text/html'].includes(type);
    for (const method of ['GET', 'HEAD']) {
      const response = await SELF.fetch(`${result.url}/file`, { method });
      expect(response.status).toBe(200);
      headers(response);
      expect(response.headers.get('content-security-policy')).toBe("default-src 'none'; sandbox");
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
