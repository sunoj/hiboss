// Worker-pool integration tests for panel publication and scoped reads.
// Covers validation, idempotency, visibility, immutable definitions, and ordered cursor pages.
// Dependencies: cloudflare:test, panel routes, auth helpers, and D1.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { hashApiKey } from '../../middleware/auth';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../../test-helpers';
import { testJson } from '../../test-request';

const BOSS_TOKEN = 'hb_panels_boss_token_0000000000000001';
const BOSS_ID = 'panels-test-boss';
const OTHER_AGENT_ID = 'panels-other-agent';
const OTHER_AGENT_KEY = 'hb_panels_other_agent_0000000000000001';

function panelBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    protocolVersion: 2,
    targetBossId: BOSS_ID,
    taskKey: 'panel-publication-test',
    sessionId: 'panels-test-session',
    title: 'Panel publication test',
    catalogId: 'hiboss.panel',
    catalogVersion: 1,
    spec: {
      root: 'main',
      elements: {
        main: { type: 'Stack', props: { direction: 'vertical' }, children: ['value'] },
        value: { type: 'Metric', props: { label: 'Completed', value: { $state: '/task/completed' } }, children: [] },
      },
    },
    stateSchema: {
      type: 'object',
      properties: { task: { type: 'object', properties: { completed: { type: 'integer', minimum: 0 } }, required: ['completed'], additionalProperties: false } },
      required: ['task'],
      additionalProperties: false,
    },
    initialState: { task: { completed: 0 } },
    summary: { stage: 'Preparing' },
    ...overrides,
  };
}

function agentHeaders(key = 'hb_test_key_0000000000000000', idempotencyKey?: string): Record<string, string> {
  return { ...authHeaders(), Authorization: `Bearer ${key}`, ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}) };
}

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

async function publish(key: string, body = panelBody(), token?: string): Promise<Response> {
  return SELF.fetch('https://test.local/api/panels', { method: 'POST', headers: agentHeaders(token, key), body: JSON.stringify(body) });
}

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Panels Boss', 'admin', BOSS_TOKEN, BOSS_ID);
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(BOSS_ID, getTestAgentId()).run();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)').bind(OTHER_AGENT_ID, 'other-panels-agent', await hashApiKey(OTHER_AGENT_KEY)).run();
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(BOSS_ID, OTHER_AGENT_ID).run();
  await env.DB.prepare("INSERT OR REPLACE INTO sessions (id, agent_id, label) VALUES (?, ?, ?), (?, ?, ?)")
    .bind('panels-test-session', getTestAgentId(), 'panels test', 'panels-other-session', OTHER_AGENT_ID, 'other panels test').run();
});

beforeEach(async () => {
  await env.DB.prepare('DELETE FROM panel_definitions').run();
  await env.DB.prepare('DELETE FROM panels').run();
});

describe('panel publication and reads', () => {
  it.each([
    [undefined, 3600, 3_600_000],
    [{ mode: 'run', ttlSeconds: 60 }, 60, 60_000],
    [{ mode: 'run', ttlSeconds: 120 }, 120, 120_000],
    [{ mode: 'run', ttlSeconds: 604800 }, 604800, 604_800_000],
  ])('persists lifecycle expiry %j with TTL %s', async (lifecycle, ttl, milliseconds) => {
    const { panelId } = await testJson(201,
      publish('panel-expiry', panelBody({ lifecycle }))) as { panelId: string };
    const panel = await readPanel(panelId) as {
      createdAt: string; lifecycle: { ttlSeconds: number; expiresAt: string };
    };
    expect(panel.lifecycle.ttlSeconds).toBe(ttl);
    expect(Date.parse(panel.lifecycle.expiresAt) - Date.parse(panel.createdAt)).toBe(milliseconds);
  });

  it.each([59, 604801, 60.5, '60', true, [], {}].map(value => [value]))(
    'rejects invalid lifecycle expiry %j', async ttlSeconds => {
    expect(await testJson(422, publish('panel-invalid-expiry', panelBody({ lifecycle: { ttlSeconds } }))))
      .toMatchObject({ error: { code: 'invalid_lifecycle', retryable: false } });
    const stored = await env.DB.prepare('SELECT COUNT(*) AS count FROM panels').first<{ count: number }>();
    expect(stored?.count).toBe(0);
  });

  it('publishes and reads its own immutable definition', async () => {
    const receipt = await testJson(201, publish('panel-own-read')) as { panelId: string };
    expect(receipt).toMatchObject({ definitionRevision: 1, metadataVersion: 1, catalogVersion: 1 });
    expect(await readPanel(receipt.panelId)).toMatchObject({
      panelId: receipt.panelId, agentName: 'test-agent', sessionLabel: 'panels test',
      definition: { definitionRevision: 1, spec: { root: 'main' } }, summary: { stage: 'Preparing' },
    });
  });

  it('resolves an omitted target for an agent with one boss', async () => {
    const body = panelBody({ targetBossId: undefined, taskKey: 'panel-resolved-defaults' });
    const receipt = await testJson(201, publish('panel-resolved-defaults', body)) as { panelId: string };
    expect(await readPanel(receipt.panelId))
      .toMatchObject({ targetBossId: BOSS_ID, sessionId: 'panels-test-session' });
  });

  it('defaults to the sole admin when an agent has several bosses', async () => {
    const secondBoss = 'panels-second-boss';
    await env.DB.prepare('INSERT OR IGNORE INTO bosses (id, name, role) VALUES (?, ?, ?)').bind(secondBoss, 'Second panels boss', 'manager').run();
    await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(secondBoss, getTestAgentId()).run();
    await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ? AND agent_id = ?').bind(BOSS_ID, getTestAgentId()).run();
    try {
      const { panelId } = await testJson(201, publish('panel-ambiguous-default', panelBody({
        targetBossId: undefined, taskKey: 'panel-ambiguous-default',
      }))) as { panelId: string };
      expect(await readPanel(panelId)).toMatchObject({ targetBossId: BOSS_ID });
      const explicit = await testJson(201,
        publish('panel-explicit-manager', panelBody({ targetBossId: secondBoss }))) as { panelId: string };
      expect(await readPanel(explicit.panelId)).toMatchObject({ targetBossId: secondBoss });
    } finally {
      await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(BOSS_ID, getTestAgentId()).run();
      await env.DB.prepare('DELETE FROM panels WHERE target_boss_id = ?').bind(secondBoss).run();
      await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ?').bind(secondBoss).run();
      await env.DB.prepare('DELETE FROM bosses WHERE id = ?').bind(secondBoss).run();
    }
  });

  it('requires an explicit target when a second admin resolves without a grant row', async () => {
    await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES ('second-admin', 'Other admin', 'admin')").run();
    try {
      expect(await testJson(400, publish('panel-two-admins', panelBody({ targetBossId: undefined }))))
        .toMatchObject({ error: { code: 'invalid_spec', path: '/targetBossId',
        message: 'targetBossId is required: 2 bosses resolve and none is the sole admin' } });
    } finally {
      await env.DB.prepare("DELETE FROM bosses WHERE id = 'second-admin'").run();
    }
  });

  it('rejects invalid specs with a path and rejects unknown catalogs', async () => {
    const invalid = await publish('panel-invalid-spec', panelBody({ spec: { root: 'main', elements: { main: { type: 'Unknown', props: {}, children: [] } } } }));
    expect(invalid.status).toBe(422);
    expect(await invalid.json()).toMatchObject({ error: { code: 'invalid_spec', path: '/spec/elements/main/type' } });
    const missingChild = await publish('panel-missing-child', panelBody({
      spec: { root: 'main', elements: { main: { type: 'Stack', props: { direction: 'vertical' }, children: ['missing'] } } },
    }));
    expect(await missingChild.json()).toMatchObject({ error: { code: 'invalid_spec', path: '/spec/elements/missing/children' } });
    const invalidInitialState = await publish('panel-invalid-initial-state', panelBody({
      spec: { root: 'main', elements: { main: { type: 'LineChart', props: { values: { $state: '/task/series' } }, children: [] } } },
      stateSchema: { type: 'object', properties: { task: { type: 'object', properties: { series: { type: 'array', items: { type: 'number' } } }, required: ['series'], additionalProperties: false } }, required: ['task'], additionalProperties: false },
      initialState: { task: { series: [12, null, 18] } },
    }));
    expect(await invalidInitialState.json()).toMatchObject({ error: { code: 'invalid_spec', path: '/initialState/task/series/1' } });
    expect(await testJson(400, publish('panel-unknown-catalog', panelBody({ catalogId: 'other.catalog' }))))
      .toMatchObject({ error: { code: 'unsupported_catalog', path: '/catalogId' } });
  });

  it('accepts a declared summary headline and rejects an undeclared headline path', async () => {
    const accepted = await publish('panel-summary-valid', panelBody({ summary: { stage: 'Running', headline: { path: '/task/completed', label: 'Open' } } }));
    expect(accepted.status).toBe(201);
    const rejected = await publish('panel-summary-invalid', panelBody({ summary: { stage: 'Running', headline: { path: '/task/missing', label: 'Missing' } } }));
    expect(rejected.status).toBe(422);
    expect(await rejected.json()).toMatchObject({ error: { code: 'invalid_spec', path: '/summary/headline/path' } });
  });

  it('returns one receipt for an idempotent retry and conflicts on a changed body', async () => {
    const firstBody = await testJson(201, publish('panel-idempotent')) as { panelId: string };
    const retry = await publish('panel-idempotent', { ...panelBody(), summary: { stage: 'Preparing' } });
    expect(await testJson(201, retry)).toMatchObject({ panelId: firstBody.panelId });
    expect(await testJson(409, publish('panel-idempotent', panelBody({ title: 'Changed body' }))))
      .toMatchObject({ error: { code: 'idempotency_conflict' } });
    const count = await env.DB.prepare('SELECT COUNT(*) AS count FROM panels').first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it('hides another agent panel with a non-disclosing 404', async () => {
    const receipt = await testJson(201, publish('panel-visibility')) as { panelId: string };
    expect(await readPanel(receipt.panelId, agentHeaders(OTHER_AGENT_KEY), 404))
      .toMatchObject({ error: { code: 'not_found' } });
    await readPanel(receipt.panelId, bossHeaders());
  });

  it('does not list another agent panel', async () => {
    // The by-id route was covered; the list route was not. Breaking the agent scope on
    // the list query left every test green, which is why this exists.
    const { panelId: minePanelId } = await testJson(201,
      publish('panel-list-scope-mine')) as { panelId: string };
    // Their own session, or the ownership check rejects the publish and the test would
    // pass with nothing to leak.
    const theirs = await publish('panel-list-scope-theirs', panelBody({ taskKey: 'theirs', sessionId: 'panels-other-session' }), OTHER_AGENT_KEY);
    expect(theirs.status).toBe(201);

    const body = await testJson(200, SELF.fetch('https://test.local/api/panels', { headers: authHeaders() })
    ) as { panels: { panelId: string; agentId?: string }[] };
    expect(body.panels.map((panel) => panel.panelId)).toEqual([minePanelId]);
  });

  it.each([
    ['paginates with a stable cursor without repeats or skips', 2],
    ['paginates one panel at a time across timestamp ties', 1],
    ['ends pagination at an exactly full page', 3],
  ])('%s', async (_title, limit) => {
    const ids: string[] = [];
    for (let number = 1; number <= 3; number++) {
      const { panelId } = await testJson(201,
        publish(`panel-page-${number}`, panelBody({ taskKey: `page-${number}` }))) as { panelId: string };
      ids.push(panelId);
      await env.DB.prepare('UPDATE panels SET created_at = ? WHERE panel_id = ?')
        .bind(`2026-10-01T00:00:0${number === 3 ? 0 : 1}.000Z`, panelId).run();
    }
    const expected = [...ids.slice(0, 2).sort().reverse(), ids[2]];
    let cursor: string | null = null;
    for (let offset = 0; offset < expected.length; offset += limit) {
      const query = `limit=${limit}` + (cursor === null ? '' : `&cursor=${encodeURIComponent(cursor)}`);
      const page = await testJson(200, SELF.fetch(`https://test.local/api/panels?${query}`,
        { headers: authHeaders() })) as { panels: { panelId: string }[]; nextCursor: string | null };
      expect(page.panels.map(panel => panel.panelId)).toEqual(expected.slice(offset, offset + limit));
      expect(page.nextCursor).toEqual(offset + limit < expected.length ? expect.any(String) : null);
      cursor = page.nextCursor;
    }
  });
});

function readPanel(id: string, headers = authHeaders(), status = 200): Promise<unknown> {
  return testJson(status, SELF.fetch(`https://test.local/api/panels/${id}`, { headers }));
}
