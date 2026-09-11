// Exercises cross-panel pending questionnaire discovery for native clients.
// Covers hidden panels, expiry, resolution, pagination, and current access boundaries.
// Dependencies: the real Worker/D1 and authenticated questionnaire fixtures.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken } from '../../../test-helpers';
import { base, BOSS, bossHeaders, create, finish, publish, publishPanel, questionnaire, setup, submit } from './support';

beforeAll(setup);
beforeEach(async () => {
  await env.DB.prepare("UPDATE interaction_requests SET expires_at = '2000-01-01T00:00:00.000Z'").run();
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access VALUES (?, ?)').bind(BOSS, getTestAgentId()).run();
});
const discover = (query = '', headers: Record<string, string> = bossHeaders) => SELF.fetch(`${base}/interaction-requests${query}`, { headers });
interface Page { requests: Array<{ requestId: string; panelId: string; title: string; blocking: boolean }>; nextCursor: string | null }

describe('pending questionnaire discovery', () => {
  it('returns scoped summaries for boss and producer without exposing answers or form contents', async () => {
    const { panelId, requestId } = await publish();
    for (const headers of [bossHeaders, authHeaders()]) {
      const response = await discover('', headers);
      expect(response.status).toBe(200);
      const page = await response.json<Page>();
      expect(page.requests).toEqual([expect.objectContaining({ requestId, panelId, title: questionnaire.title, blocking: true })]);
      expect(page.requests[0]).not.toHaveProperty('definition');
      expect(page.requests[0]).not.toHaveProperty('answers');
    }
  });
  it('keeps pending input discoverable after panel visibility expires or the boss archives it', async () => {
    const { panelId, requestId } = await publish();
    await env.DB.prepare("UPDATE panels SET lifecycle_json = json_set(lifecycle_json, '$.expiresAt', '2000-01-01T00:00:00.000Z') WHERE panel_id = ?").bind(panelId).run();
    await env.DB.prepare("INSERT INTO panel_preferences (panel_id,boss_id,preference_version,value_json) VALUES (?, ?, 1, ?)").bind(panelId, BOSS, JSON.stringify({ preferenceVersion: 1, placement: 'archived' })).run();
    expect((await (await discover()).json<Page>()).requests.map(row => row.requestId)).toContain(requestId);
  });
  it('includes optional and paused input and removes accepted, withdrawn, and expired requests', async () => {
    const panelId = await publishPanel();
    const pending = await (await create(panelId, { ...questionnaire, blocking: false })).json<{ requestId: string }>();
    expect((await finish(panelId, { action: 'pause' })).status).toBe(200);
    expect((await (await discover()).json<Page>()).requests[0]?.blocking).toBe(false);
    expect((await submit(pending.requestId)).status).toBe(201);
    const expired = await publish();
    await env.DB.prepare("UPDATE interaction_requests SET expires_at = '2000-01-01T00:00:00.000Z' WHERE request_id = ?").bind(expired.requestId).run();
    const withdrawn = await publish();
    await finish(withdrawn.panelId, { openRequests: 'withdraw', withdrawalReason: 'Finished' });
    expect((await (await discover()).json<Page>()).requests).toEqual([]);
  });
  it('hides input from other bosses and after access is revoked', async () => {
    await publish();
    await seedBossToken('Other', 'admin', 'hb_discovery_other', 'discovery-other');
    expect((await (await discover('', { Authorization: 'Bearer hb_discovery_other', 'Content-Type': 'application/json' })).json<Page>()).requests).toEqual([]);
    await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ?').bind(BOSS).run();
    expect((await (await discover()).json<Page>()).requests).toEqual([]);
    expect((await SELF.fetch(`${base}/interaction-requests`)).status).toBe(401);
  });
  it('paginates without repeating or skipping requests and validates cursor input', async () => {
    const panelId = await publishPanel();
    for (let index = 0; index < 5; index++) await create(panelId);
    const ids: string[] = [];
    let cursor: string | null = null;
    do {
      const response = await discover(`?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
      expect(response.status).toBe(200);
      const page: Page = await response.json();
      expect(page.requests.length).toBeLessThanOrEqual(2);
      ids.push(...page.requests.map(row => row.requestId));
      cursor = page.nextCursor;
    } while (cursor);
    expect(new Set(ids).size).toBe(5);
    for (const query of ['?limit=0', '?limit=101', '?cursor=invalid']) expect((await discover(query)).status).toBe(400);
  });
});
