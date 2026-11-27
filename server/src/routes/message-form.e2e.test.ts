// Form asks: an ask whose question is one catalog v2 input, answered only with validated answers.
// Covers send validation, the 409 for a text reply, answer validation, storage and closing.
// Depends on the worker API, D1 test fixtures and the agent/boss test credentials.

import { testRequest, testJson } from '../test-request';
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const BOSS_TOKEN = `hb_boss_${'fa'.repeat(16)}`;
const ranked = {
  catalogVersion: 2,
  input: {
    type: 'RankedChoice',
    props: {
      label: 'Order the follow-ups',
      value: { $bindState: '/form/answer' },
      options: [{ id: 'sync', label: 'Fix sync' }, { id: 'settings', label: 'Split settings' }, { id: 'flag', label: 'Rename flag' }],
    },
  },
};
const review = {
  catalogVersion: 2,
  input: {
    type: 'ItemReview',
    props: {
      label: 'Pre-release checks',
      value: { $bindState: '/form/answer' },
      items: [{ id: 'changelog', label: 'Changelog read' }, { id: 'rollback', label: 'Rollback tested' }],
      verdicts: [{ id: 'confirmed', label: 'Confirmed' }, { id: 'not_confirmed', label: 'Cannot confirm', requiresNote: true }],
    },
  },
};

beforeAll(async () => {
  await seedDatabase();
  const bossId = await seedBossToken('Form Boss', 'admin', BOSS_TOKEN, 'form-boss');
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, getTestAgentId()).run();
});

function send(payload: Record<string, unknown>): Promise<Response> {
  return testRequest('POST', 'https://test.local/api/messages', authHeaders(),
    { body: 'Question', mode: 'blocking', ...payload });
}

function reply(parentId: string, payload: Record<string, unknown>): Promise<Response> {
  return testRequest('POST', `http://localhost/api/boss/messages/${parentId}/reply`,
    { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' }, payload);
}

async function stored(id: string): Promise<{ metadata: Record<string, unknown> | null }> {
  return await testJson(200, testRequest('GET', `https://test.local/api/messages/${id}`, authHeaders())) as
    { metadata: Record<string, unknown> | null };
}

async function askWith(form: unknown): Promise<string> {
  const { id } = await testJson(201, send({ metadata: { form } })) as { id: string };
  expect((await stored(id)).metadata?.form).toEqual(form);
  return id;
}

describe('sending a form ask', () => {
  it('rejects options, a default, an async mode and a loose binding', async () => {
    expect((await send({ metadata: { form: ranked }, options: ['A', 'B'] })).status).toBe(400);
    expect((await send({ metadata: { form: ranked, default_option: 'sync' } })).status).toBe(400);
    expect((await send({ metadata: { form: ranked }, mode: 'async' })).status).toBe(400);
    const loose = { ...ranked, input: { ...ranked.input, props: { ...ranked.input.props, value: { $bindState: '/form/other' } } } };
    expect((await send({ metadata: { form: loose } })).status).toBe(400);
  });

  it('refuses a form ask to another agent, whose text reply would close it', async () => {
    const res = await send({ metadata: { form: ranked }, to: 'some-peer' });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('goes to the boss');
  });

  it('rejects catalog v1, a v1 input and two inputs', async () => {
    expect((await send({ metadata: { form: { ...ranked, catalogVersion: 1 } } })).status).toBe(400);
    const select = { catalogVersion: 2, input: { type: 'Select', props: { label: 'x', value: { $bindState: '/form/answer' }, options: [{ id: 'a', label: 'A' }] } } };
    expect((await send({ metadata: { form: select } })).status).toBe(400);
    expect((await send({ metadata: { form: { ...ranked, extra: review.input } } })).status).toBe(400);
  });
});

describe('answering a form ask', () => {
  it('refuses a text reply with 409 so an old client cannot answer it', async () => {
    const id = await askWith(ranked);
    const res = await reply(id, { body: 'sync first' });
    expect(res.status).toBe(409);
  });

  it('rejects an answer outside the derived schema and keeps the ask open', async () => {
    const id = await askWith(ranked);
    expect((await reply(id, { body: 'Order', answers: ['sync', 'sync', 'flag'] })).status).toBe(400);
    expect((await reply(id, { body: 'Order', answers: ['sync', 'flag'] })).status).toBe(400);
    const ok = await reply(id, { body: 'Fix sync, Rename flag, Split settings', answers: ['sync', 'flag', 'settings'] });
    expect(ok.status).toBe(201);
  });

  it('stores the answers on the reply and closes the ask', async () => {
    const id = await askWith(review);
    const answers = { changelog: { verdict: 'confirmed' }, rollback: { verdict: 'not_confirmed', note: 'Old schema only' } };
    const stored = await testJson(201, reply(id, { body: 'Changelog: confirmed. Rollback: cannot confirm.', answers })) as {
      reply_to: string; metadata: { answers: unknown };
    };
    expect(stored.reply_to).toBe(id);
    expect(stored.metadata.answers).toEqual(answers);
    const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id).first<{ status: string }>();
    expect(parent?.status).toBe('replied');
    expect((await reply(id, { body: 'again', answers })).status).toBe(409);
  });

  it('requires the note a verdict asks for', async () => {
    const id = await askWith(review);
    const answers = { changelog: { verdict: 'confirmed' }, rollback: { verdict: 'not_confirmed' } };
    expect((await reply(id, { body: 'Checks', answers })).status).toBe(400);
  });

  it('keeps buttons on an older option ask whose metadata happens to hold a form', async () => {
    await env.DB.prepare("INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Pick', 'sent', 'normal', ?)")
      .bind('legacy-form-options', getTestAgentId(), JSON.stringify({ options: ['A', 'B'], form: ranked })).run();
    expect((await reply('legacy-form-options', { body: 'A' })).status).toBe(201);
  });

  it('refuses answers on an ordinary message and strips answers an agent sends', async () => {
    const plain = await testJson(201, send({ metadata: { answers: ['sync'] } })) as { id: string };
    expect((await stored(plain.id)).metadata?.answers).toBeUndefined();
    expect((await reply(plain.id, { body: 'Ok', answers: ['sync'] })).status).toBe(400);
  });
});
