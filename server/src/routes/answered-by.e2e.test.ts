// HTTP coverage for server-owned answering-device attribution and legacy replies.
// Exercises option/message replies, history JSON, and resolved stream replay.
// Depends on seeded D1, bearer boss auth, and the Worker API.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { readAnsweredBy, stampAnsweredBy, type AnsweredBy } from '../answered-by';
import type { ClientId } from '../boss-clients/types';
import type { MessageResponse } from '../types';

const TOKEN = 'hb_boss_answering_device_test_0001';
const LEGACY_TOKEN = 'hb_boss_answering_legacy_test_0001';
const DEVICE: AnsweredBy = { client_id: 'answering-phone', kind: 'ios', label: "Ming's iPhone" };
const SPOOF = { client_id: 'fake', kind: 'macos', label: 'Fake Mac' };
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  bossId = await seedBossToken('Device Boss', 'admin', TOKEN);
  await seedBossToken('Legacy Boss', 'admin', LEGACY_TOKEN);
  await env.DB.prepare('INSERT INTO boss_clients (id, boss_id, kind, label) VALUES (?, ?, ?, ?)')
    .bind(DEVICE.client_id, bossId, DEVICE.kind, DEVICE.label).run();
  await env.DB.prepare('UPDATE boss_tokens SET client_id = ? WHERE token_hash = ?')
    .bind(DEVICE.client_id, await hashApiKey(TOKEN)).run();
});

describe('answering device attribution', () => {
  it.each([false, true])('replaces supplied attribution on a reply (options=%s)', async (options) => {
    const id = await parent(options);
    const response = await reply(id, TOKEN);
    expect(response.status).toBe(201);
    const stored = await response.json() as MessageResponse;
    expect(stored.metadata?.['answered_by']).toEqual(DEVICE);
    expect(stored.answered_by).toEqual(DEVICE);
    expect(stored.metadata?.['source']).toBe('api');
    const detail = await SELF.fetch(`http://localhost/api/boss/messages/${id}`, { headers: headers(TOKEN) });
    const message = await detail.json() as MessageResponse;
    expect(message.replies?.[0]?.answered_by).toEqual(DEVICE);
    const history = await SELF.fetch('http://localhost/api/boss/messages?limit=100&direction=all', {
      headers: headers(TOKEN),
    });
    const page = await history.json() as { messages: MessageResponse[] };
    expect(page.messages.find(row => row.id === stored.id)?.metadata?.['answered_by']).toEqual(DEVICE);
  });

  it('adds the device to a live resolution while preserving the legacy event fields', async () => {
    const id = await parent(true);
    const response = await SELF.fetch('http://localhost/api/boss/stream?options=true', {
      headers: headers(TOKEN),
    });
    const reader = response.body!.getReader();
    expect(new TextDecoder().decode((await reader.read()).value)).toContain(id);
    expect((await reply(id, TOKEN)).status).toBe(201);
    let event: Record<string, unknown> | undefined;
    try {
      while (!event) {
        const chunk = new TextDecoder().decode((await reader.read()).value);
        for (const data of chunk.split('\n').filter(line => line.startsWith('data: '))) {
          const decoded = JSON.parse(data.slice(6)) as Record<string, unknown>;
          if (decoded['id'] === id) event = decoded;
        }
      }
      expect(event['answered_by']).toEqual(DEVICE);
      const { id: messageId, status, answer, source } = event;
      expect({ id: messageId, status, answer, source })
        .toEqual({ id, status: 'replied', answer: 'Ship', source: 'api' });
    } finally { await reader.cancel(); }
  });

  it('strips supplied attribution when the token has no client', async () => {
    const response = await reply(await parent(false), LEGACY_TOKEN);
    expect(response.status).toBe(201);
    const stored = await response.json() as MessageResponse;
    expect(stored.metadata?.['answered_by']).toBeUndefined();
    expect(stored.answered_by).toBeUndefined();
    expect(stored.metadata?.['source']).toBe('api');
  });

  it('removes untrusted metadata and refuses a client belonging to another boss', async () => {
    const metadata = { answered_by: SPOOF, source: 'api', action: 'Ship' };
    const clientId = DEVICE.client_id as ClientId;
    expect(await stampAnsweredBy(env, bossId, clientId, metadata))
      .toEqual({ ...metadata, answered_by: DEVICE });
    expect(await stampAnsweredBy(env, 'other-boss', clientId, metadata))
      .toEqual({ source: 'api', action: 'Ship' });
    expect(await stampAnsweredBy(env, bossId, null, metadata))
      .toEqual({ source: 'api', action: 'Ship' });
  });

  it('reads only the additive attribution shape', () => {
    expect(readAnsweredBy(null)).toBeUndefined();
    for (const value of [null, [], 'fake', {}, { ...DEVICE, kind: 'api' }, { ...DEVICE, label: 9 }]) {
      expect(readAnsweredBy({ answered_by: value })).toBeUndefined();
    }
    expect(readAnsweredBy({ answered_by: DEVICE })).toEqual(DEVICE);
  });
});

async function parent(options: boolean): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'Ship?', 'sent', 'normal', ?, ?)`)
    .bind(id, getTestAgentId(), JSON.stringify(options ? { options: ['Ship'] } : {}),
      new Date(Date.now() + 60_000).toISOString()).run();
  return id;
}

function headers(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

function reply(id: string, token: string): Promise<Response> {
  return SELF.fetch(`http://localhost/api/boss/messages/${id}/reply`, {
    method: 'POST', headers: headers(token),
    body: JSON.stringify({ body: 'Ship', answered_by: SPOOF, metadata: { answered_by: SPOOF } }),
  });
}
