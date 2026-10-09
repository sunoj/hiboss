// Verifies agent write sources and unambiguous boss selection through HTTP and D1.
// Uses shared Box fixtures for JSON and multipart requests.
import { env } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, expect, it } from 'vitest';
import { ADMIN, OWNER, create, request, resetBox, seedBox, upload, type Item } from './box-test-helpers';

beforeAll(seedBox);
beforeEach(() => resetBox());
afterEach(() => resetBox());

it.each(['ios-share', 'mac-share', 'mac-drop', 'cli'])(
  'stores cli for agent JSON and multipart writes requesting %s', async source => {
    const json = await create({ text: 'agent source', boss: OWNER, source }, 'agent');
    const response = await upload('image/png', 4, { boss: OWNER, source }, 'agent');
    expect(response.status).toBe(201);
    const multipart = await response.json() as Item;
    for (const item of [json, multipart]) {
      expect(item.source).toBe('cli');
      const stored = await env.DB.prepare('SELECT source FROM box_items WHERE id = ?')
        .bind(item.id).first();
      expect(stored).toEqual({ source: 'cli' });
    }
  });

it('returns 409 naming ids for duplicate resolved boss names in JSON and multipart writes', async () => {
  await env.DB.prepare('UPDATE bosses SET name = ? WHERE id = ?').bind('Box Owner', ADMIN).run();
  try {
    const responses = [
      await request('', 'POST', { text: 'ambiguous', boss: 'Box Owner' }, 'agent'),
      await upload('image/png', 4, { boss: 'Box Owner' }, 'agent'),
    ];
    for (const response of responses) {
      expect(response.status).toBe(409);
      const message = await response.text();
      for (const id of [OWNER, ADMIN]) expect(message).toContain(`Box Owner (${id})`);
      expect(message).not.toContain('Box Other');
    }
    expect(await env.DB.prepare('SELECT id FROM box_items').all()).toMatchObject({ results: [] });
    expect((await env.ATTACHMENTS.list({ prefix: 'box/' })).objects).toEqual([]);
    for (const id of [OWNER, ADMIN]) {
      expect((await create({ text: 'by id', boss: id }, 'agent')).boss_id).toBe(id);
    }
  } finally {
    await env.DB.prepare('UPDATE bosses SET name = ? WHERE id = ?').bind('Box Admin', ADMIN).run();
  }
});

it('prefers an exact boss id over another resolved boss name', async () => {
  await env.DB.prepare('UPDATE bosses SET name = ? WHERE id = ?').bind(OWNER, ADMIN).run();
  try {
    expect((await create({ text: 'exact id', boss: OWNER }, 'agent')).boss_id).toBe(OWNER);
    const response = await upload('image/png', 4, { boss: OWNER }, 'agent');
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ boss_id: OWNER });
  } finally {
    await env.DB.prepare('UPDATE bosses SET name = ? WHERE id = ?').bind('Box Admin', ADMIN).run();
  }
});
