// Receipt status only advances (sent → delivered → read) on every boss path.
// Covers PATCH /api/boss/messages/:id (boss token) and PATCH /api/boss/inbox/:id (boss agent).
// Depends on the Worker (SELF), seeded D1, and test-helpers.

import { testRequest } from '../test-request';
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const BOSS_TOKEN = 'hb_receipt_boss_00000000000000';
const BOSS_AGENT_KEY = 'hb_receipt_agent_0000000000000';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Receipt Boss', 'admin', BOSS_TOKEN, 'receipt-boss');
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('receipt-boss-agent', 'receipt-boss-agent', await hashApiKey(BOSS_AGENT_KEY)).run();
  await env.DB.prepare("INSERT OR IGNORE INTO bosses (id, name, role, agent_id) VALUES ('receipt-agent-boss', 'Receipt Agent Boss', 'admin', 'receipt-boss-agent')").run();
});

async function message(status: string): Promise<string> {
  const id = `receipt-${crypto.randomUUID()}`;
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status)
    VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'hello', ?)`).bind(id, getTestAgentId(), status).run();
  return id;
}

async function statusOf(id: string): Promise<string | undefined> {
  return (await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id).first<{ status: string }>())?.status;
}

const paths = [
  { name: 'boss token', url: (id: string) => `http://localhost/api/boss/messages/${id}`, bearer: BOSS_TOKEN },
  { name: 'boss agent', url: (id: string) => `http://localhost/api/boss/inbox/${id}`, bearer: BOSS_AGENT_KEY },
];

describe.each(paths)('receipt PATCH via $name', ({ url, bearer }) => {
  const patch = (id: string, status: string) => testRequest('PATCH', url(id),
    { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' }, { status });

  it('keeps a read message read when delivered arrives late', async () => {
    const id = await message('read');
    const res = await patch(id, 'delivered');
    expect(res.status).toBe(200);
    expect(((await res.json()) as { status: string }).status).toBe('read');
    expect(await statusOf(id)).toBe('read');
  });

  it('still advances sent to delivered and delivered to read', async () => {
    const id = await message('sent');
    expect((await patch(id, 'delivered')).status).toBe(200);
    expect(await statusOf(id)).toBe('delivered');
    expect((await patch(id, 'read')).status).toBe(200);
    expect(await statusOf(id)).toBe('read');
  });

  it('rejects a receipt for a replied message', async () => {
    const id = await message('replied');
    expect((await patch(id, 'read')).status).toBe(409);
    expect(await statusOf(id)).toBe('replied');
  });
});
