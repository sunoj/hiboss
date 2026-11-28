// Tests one-time enrollment key delivery over the status poll.
// Uses the Worker and seeded D1 to exercise concurrent requests.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const AGENT_ID = '12345678abcdef0123456789abcdef01';
const KEY = 'test-delivered-key';
const NAME = 'join-notice-agent';
const DEVICE = 'join-notice-device';
const DEVICE_ID = 'd_join_notice';
const TOKEN = 'join-notice-token';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO devices (id, label) VALUES (?, ?)').bind(DEVICE_ID, DEVICE).run();
  await env.DB.prepare('INSERT INTO api_keys (id, name, device_id) VALUES (?, ?, ?)')
    .bind(AGENT_ID, NAME, DEVICE_ID).run();
});

afterEach(async () => {
  await env.DB.prepare('DELETE FROM join_requests WHERE device_label = ?').bind(DEVICE).run();
});

const PROFILES = JSON.stringify([{ profile: 'claude', name: NAME }]);
const DELIVERY = JSON.stringify({ device_id: DEVICE_ID, profiles: [{ profile: 'claude', name: NAME, agent_id: AGENT_ID, key: KEY }] });

async function insertRequest(status: 'pending' | 'approved'): Promise<void> {
  await env.DB.prepare(`INSERT INTO join_requests (poll_token_hash, status, device_label, device_id, profiles, delivery)
    VALUES (?, ?, ?, ?, ?, ?)`)
    .bind(await hashApiKey(TOKEN), status, DEVICE, status === 'approved' ? DEVICE_ID : null, PROFILES,
      status === 'approved' ? DELIVERY : null).run();
}

function deliveredKeys(response: Record<string, unknown>): unknown[] {
  const profiles = response['profiles'] as Array<Record<string, unknown>> | undefined;
  return (profiles ?? []).map(profile => profile['key']).filter(Boolean);
}

describe('GET /api/join/status key delivery', () => {
  it('delivers the key to exactly one of two racing polls', async () => {
    await insertRequest('approved');
    const responses = await Promise.all([pollStatus(), pollStatus()]);
    expect(responses.flatMap(deliveredKeys)).toEqual([KEY]);
  });
});

async function pollStatus(): Promise<Record<string, unknown>> {
  const response = await SELF.fetch(`https://test.local/api/join/status?token=${TOKEN}`);
  expect(response.status).toBe(200);
  return response.json() as Promise<Record<string, unknown>>;
}
