// Seeds the Box migration and identities for real HTTP/D1/R2 tests.
// Exports typed requests and upload helpers; shares the existing auth fixtures.
import { env, SELF } from 'cloudflare:test';
import { expect } from 'vitest';
import migration from '../migrations/0050_box_items.sql?raw';
import agentMigration from '../migrations/0051_box_item_agent.sql?raw';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from './test-helpers';
import type { BoxItem } from './box/types';

export const OWNER = 'box-owner';
export const OTHER = 'box-other';
export const ADMIN = 'box-admin';
export type Item = BoxItem;
export interface Page { items: Item[]; next_cursor: string | null }

export async function seedBox(): Promise<void> {
  await seedDatabase();
  const statements = migration.match(/CREATE TRIGGER[\s\S]*?END;|CREATE[\s\S]*?;/g) ?? [];
  await env.DB.batch(statements.map(sql => env.DB.prepare(sql)));
  const agentStatements = agentMigration.replace(/^--.*$/gm, '').split(';')
    .map(sql => sql.trim()).filter(Boolean);
  await env.DB.batch(agentStatements.map(sql => env.DB.prepare(sql)));
  await seedBossToken('Box Owner', 'viewer', OWNER, OWNER);
  await seedBossToken('Box Other', 'manager', OTHER, OTHER);
  await seedBossToken('Box Admin', 'admin', ADMIN, ADMIN);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(OWNER, getTestAgentId()).run();
}

export async function resetBox(agentIds: readonly string[] = [getTestAgentId()]): Promise<void> {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM box_idempotency'),
    env.DB.prepare('DELETE FROM box_items'),
    env.DB.prepare('UPDATE bosses SET archived_at = NULL WHERE id IN (?, ?, ?)')
      .bind(OWNER, OTHER, ADMIN),
    env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id IN (?, ?, ?)')
      .bind(OWNER, OTHER, ADMIN),
    ...agentIds.map(agentId => env.DB.prepare(
      'INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)',
    ).bind(OWNER, agentId)),
  ]);
  let cursor: string | undefined;
  do {
    const objects = await env.ATTACHMENTS.list({ prefix: 'box/', cursor });
    if (objects.objects.length) await env.ATTACHMENTS.delete(objects.objects.map(object => object.key));
    cursor = objects.truncated ? objects.cursor : undefined;
  } while (cursor);
}

export function request(path = '', method = 'GET', body?: unknown, token = OWNER,
  extra: Record<string, string> = {}): Promise<Response> {
  const headers = token === 'agent' ? authHeaders() : { Authorization: `Bearer ${token}` };
  return SELF.fetch(`https://test.local/api/box/items${path}`, {
    method, headers: { ...headers, 'Content-Type': 'application/json', ...extra },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

export async function create(body: Record<string, unknown>, token = OWNER): Promise<Item> {
  const response = await request('', 'POST', body, token);
  expect(response.status, await response.clone().text()).toBe(201);
  return response.json() as Promise<Item>;
}

export function upload(type = 'image/png', bytes = 10, meta: Record<string, unknown> = {},
  token = OWNER, key?: string): Promise<Response> {
  const form = new FormData();
  form.set('meta', JSON.stringify({ source: 'ios-share', ...meta }));
  form.set('file', new File([new Uint8Array(bytes).fill(65)], 'reference', { type }));
  const authorization = token === 'agent' ? authHeaders().Authorization : `Bearer ${token}`;
  return SELF.fetch('https://test.local/api/box/items', {
    method: 'POST', headers: { Authorization: authorization,
      ...(key ? { 'Idempotency-Key': key } : {}) }, body: form,
  });
}

export async function page(path: string, token = OWNER): Promise<Page> {
  const response = await request(path, 'GET', undefined, token);
  expect(response.status, await response.clone().text()).toBe(200);
  return response.json() as Promise<Page>;
}
