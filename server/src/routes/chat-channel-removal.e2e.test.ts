// Covers removed HTTP routes and historical Discord and Telegram message reads.
// Uses the Worker with the current D1 schema and seeded credentials.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const origin = 'https://test.local';
const bossToken = 'history-boss-token';
const sources = ['discord', 'telegram'] as const;

beforeAll(async () => {
  await seedDatabase();
  const bossId = await seedBossToken('History Boss', 'admin', bossToken);
  await env.DB.prepare('UPDATE bosses SET agent_id = ? WHERE id = ?').bind(getTestAgentId(), bossId).run();
  for (const source of sources) {
    await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, metadata)
      VALUES (?, ?, 'agent_to_boss', 'async', ?, 'Historical message', ?)`)
      .bind(`history-${source}`, getTestAgentId(), source,
        JSON.stringify({ source, provenance: { version: 1, source } })).run();
  }
});

it.each([
  ['POST', '/api/webhooks/discord'],
  ['POST', '/api/webhooks/discord-interactions'],
  ['POST', '/api/webhooks/telegram'],
  ['POST', '/api/webhooks/telegram/register-commands'],
  ['GET', '/api/channels'],
  ['GET', '/api/channels/stats'],
  ['PUT', '/api/channels/discord'],
  ['GET', '/api/boss/channels'],
  ['PATCH', '/api/boss/channels/example'],
  ['GET', '/api/routing-rules'],
  ['GET', '/api/boss/routing-rules'],
  ['GET', '/api/discord-gateway/status'],
  ['POST', '/api/discord-gateway/connect'],
  ['POST', '/api/discord-gateway/disconnect'],
  ['GET', '/api/boss/me/external-accounts'],
  ['GET', '/api/bosses/example/external-accounts'],
  ['GET', '/api/boss/providers'],
  ['POST', '/api/boss/destinations'],
  ['POST', '/api/messages/example/forward'],
  ['POST', '/api/boss/messages/example/forward'],
])('%s %s returns 404', async (method, path) => {
  expect((await SELF.fetch(origin + path, { method })).status).toBe(404);
});

it.each(sources)('keeps %s provenance on agent history, boss history and inbox reads', async source => {
  const id = `history-${source}`;
  const expected = { id, channel: source, metadata: { source, provenance: { version: 1, source } } };
  for (const [path, headers] of [
    ['/api/messages', authHeaders()],
    ['/api/boss/messages', { Authorization: `Bearer ${bossToken}` }],
    ['/api/boss/inbox', authHeaders()],
  ] as const) {
    const list = await SELF.fetch(origin + path, { headers });
    expect(list.status).toBe(200);
    expect(await list.json()).toMatchObject({ messages: expect.arrayContaining([expect.objectContaining(expected)]) });
    const detail = await SELF.fetch(`${origin}${path}/${id}`, { headers });
    expect(detail.status).toBe(200);
    expect(await detail.json()).toMatchObject(expected);
  }
});
