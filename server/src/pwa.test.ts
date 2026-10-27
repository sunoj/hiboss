// Integration coverage for the retired embedded dashboard and retained message API.
// Checks retired paths, the API root, and reaction identities without a browser.
// Depends on cloudflare:test, database fixtures, and the production Worker.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from './test-helpers';

beforeAll(seedDatabase);

describe('worker routes after dashboard retirement', () => {
  it('serves the API root without an embedded application', async () => {
    const response = await SELF.fetch('https://test.local/');
    expect(response.status).toBe(200);
    expect(await response.text()).toBe('hiboss server');
    expect(response.headers.get('x-request-id')).toBeTruthy();
  });

  it('does not serve retired dashboard or PWA assets', async () => {
    for (const path of ['/dashboard', '/manifest.json', '/icon.svg', '/sw.js']) {
      const response = await SELF.fetch(`https://test.local${path}`);
      expect(response.status, path).toBe(404);
      expect(await response.text(), path).toBe('404 Not Found');
      expect(response.headers.get('x-request-id'), path).toBeTruthy();
    }
  });

  it('preserves agent, boss and legacy reaction identities in message reads', async () => {
    const reactions = [
      { emoji: '👍', actor: 'agent', actor_id: 'agent-1' },
      { emoji: '🔥', actor: 'boss', actor_id: '123' },
      { emoji: '👍', user: 'Alice' },
    ];
    await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, body, metadata)
      VALUES (?, ?, 'agent_to_boss', 'async', 'reactions', ?)`)
      .bind('retired-dashboard-reactions', getTestAgentId(), JSON.stringify({ reactions })).run();
    const response = await SELF.fetch('https://test.local/api/messages/retired-dashboard-reactions', {
      headers: authHeaders(),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ metadata: { reactions } });
  });
});
