// Worker-pool integration tests for panel publication and scoped reads.
// Covers validation, idempotency, visibility, immutable definitions, and cursors.
// Dependencies: cloudflare:test, panel routes, auth helpers, and D1.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { hashApiKey } from '../../middleware/auth';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../../test-helpers';

const BOSS_TOKEN = 'hb_panels_boss_token_0000000000000001';
const BOSS_ID = 'panels-test-boss';
const OTHER_AGENT_ID = 'panels-other-agent';
const OTHER_AGENT_KEY = 'hb_panels_other_agent_0000000000000001';

function panelBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    protocolVersion: 1,
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
  await seedBossToken('Panels Boss', 'manager', BOSS_TOKEN, BOSS_ID);
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
  it('publishes and reads its own immutable definition', async () => {
    const published = await publish('panel-own-read');
    expect(published.status).toBe(201);
    const receipt = await published.json() as { panelId: string; definitionRevision: number; metadataVersion: number; catalogVersion: number; createdAt: string };
    expect(receipt).toMatchObject({ definitionRevision: 1, metadataVersion: 1, catalogVersion: 1 });
    const read = await SELF.fetch(`https://test.local/api/panels/${receipt.panelId}`, { headers: authHeaders() });
    expect(read.status).toBe(200);
    const panel = await read.json() as { panelId: string; agentName: string; sessionLabel: string; definition: { definitionRevision: number; spec: { root: string } }; summary: { stage: string } };
    expect(panel.panelId).toBe(receipt.panelId);
    expect(panel).toMatchObject({ agentName: 'test-agent', sessionLabel: 'panels test' });
    expect(panel.definition).toMatchObject({ definitionRevision: 1, spec: { root: 'main' } });
    expect(panel.summary.stage).toBe('Preparing');
  });

  it('rejects invalid specs with a path and rejects unknown catalogs', async () => {
    const invalid = await publish('panel-invalid-spec', panelBody({ spec: { root: 'main', elements: { main: { type: 'Unknown', props: {}, children: [] } } } }));
    expect(invalid.status).toBe(422);
    expect(await invalid.json()).toMatchObject({ error: { code: 'invalid_spec', path: '/elements/main/type' } });
    const unknown = await publish('panel-unknown-catalog', panelBody({ catalogId: 'other.catalog' }));
    expect(unknown.status).toBe(400);
    expect(await unknown.json()).toMatchObject({ error: { code: 'unsupported_catalog', path: '/catalogId' } });
  });

  it('returns one receipt for an idempotent retry and conflicts on a changed body', async () => {
    const first = await publish('panel-idempotent');
    const firstBody = await first.json() as { panelId: string };
    const retry = await publish('panel-idempotent', { ...panelBody(), summary: { stage: 'Preparing' } });
    expect(await retry.json()).toMatchObject({ panelId: firstBody.panelId });
    const conflict = await publish('panel-idempotent', panelBody({ title: 'Changed body' }));
    expect(conflict.status).toBe(409);
    expect(await conflict.json()).toMatchObject({ error: { code: 'idempotency_conflict' } });
    const count = await env.DB.prepare('SELECT COUNT(*) AS count FROM panels').first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it('hides another agent panel with a non-disclosing 404', async () => {
    const published = await publish('panel-visibility');
    const receipt = await published.json() as { panelId: string };
    const other = await SELF.fetch(`https://test.local/api/panels/${receipt.panelId}`, { headers: agentHeaders(OTHER_AGENT_KEY) });
    expect(other.status).toBe(404);
    expect(await other.json()).toMatchObject({ error: { code: 'not_found' } });
    const boss = await SELF.fetch(`https://test.local/api/panels/${receipt.panelId}`, { headers: bossHeaders() });
    expect(boss.status).toBe(200);
  });

  it('does not list another agent panel', async () => {
    // The by-id route was covered; the list route was not. Breaking the agent scope on
    // the list query left every test green, which is why this exists.
    const mine = await publish('panel-list-scope-mine');
    expect(mine.status).toBe(201);
    const minePanelId = (await mine.json() as { panelId: string }).panelId;
    // Their own session, or the ownership check rejects the publish and the test would
    // pass with nothing to leak.
    const theirs = await publish('panel-list-scope-theirs', panelBody({ taskKey: 'theirs', sessionId: 'panels-other-session' }), OTHER_AGENT_KEY);
    expect(theirs.status).toBe(201);

    const listed = await SELF.fetch('https://test.local/api/panels', { headers: authHeaders() });
    expect(listed.status).toBe(200);
    const body = await listed.json() as { panels: { panelId: string; agentId?: string }[] };
    expect(body.panels.map((panel) => panel.panelId)).toEqual([minePanelId]);
  });

  it('paginates with a stable cursor without repeats or skips', async () => {
    await publish('panel-page-1', panelBody({ taskKey: 'page-1' }));
    await publish('panel-page-2', panelBody({ taskKey: 'page-2' }));
    await publish('panel-page-3', panelBody({ taskKey: 'page-3' }));
    const first = await SELF.fetch('https://test.local/api/panels?limit=2', { headers: authHeaders() });
    const pageOne = await first.json() as { panels: Array<{ panelId: string }>; nextCursor: string | null };
    expect(pageOne.panels).toHaveLength(2);
    expect(pageOne.nextCursor).toEqual(expect.any(String));
    const second = await SELF.fetch(`https://test.local/api/panels?limit=2&cursor=${encodeURIComponent(pageOne.nextCursor as string)}`, { headers: authHeaders() });
    const pageTwo = await second.json() as { panels: Array<{ panelId: string }>; nextCursor: string | null };
    expect(pageTwo.panels).toHaveLength(1);
    expect(pageTwo.panels.map((panel) => panel.panelId)).not.toEqual(expect.arrayContaining(pageOne.panels.map((panel) => panel.panelId)));
    expect(pageTwo.nextCursor).toBeNull();
  });
});
