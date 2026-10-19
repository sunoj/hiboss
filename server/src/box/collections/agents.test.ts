// Covers agent collection creation scope and rename access.
// Uses the existing authenticated Box fixtures and real D1 routes.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import { OWNER, OTHER, resetBox, seedBox } from '../../box-test-helpers';
import { collections, newCollection } from './test-helpers';

beforeAll(seedBox);
beforeEach(() => resetBox());

it('resolves create bosses by ID or name and reports ambiguous or unknown bosses', async () => {
  const ambiguous = await collections('', 'POST', { name: 'Choose' }, 'agent');
  expect(ambiguous.status).toBe(409);
  expect(await ambiguous.text()).toContain('Box Owner');
  for (const boss of [OWNER, 'Box Owner']) {
    const response = await collections('', 'POST', { name: `Agent ${boss}`, boss }, 'agent');
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ boss_id: OWNER });
  }
  for (const boss of [OTHER, 'missing']) {
    expect((await collections('', 'POST', { name: 'Hidden', boss }, 'agent')).status).toBe(404);
  }
});

it('creates without a boss when exactly one is readable', async () => {
  await env.DB.prepare('UPDATE bosses SET archived_at = '2026-01-01' WHERE role = 'admin'').run();
  const response = await collections('', 'POST', { name: 'Only boss' }, 'agent');
  expect(response.status).toBe(201);
  expect(await response.json()).toMatchObject({ boss_id: OWNER });
});

it('renames readable collections and hides unreadable and missing collections', async () => {
  const own = await newCollection('Own');
  const foreign = await newCollection('Hidden', OTHER);
  const response = await collections(`/${own.id}`, 'PATCH', { name: 'Agent name' }, 'agent');
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ name: 'Agent name' });
  for (const id of [foreign.id, 'bc_missing']) {
    expect((await collections(`/${id}`, 'PATCH', { name: 'Denied' }, 'agent')).status).toBe(404);
  }
});
