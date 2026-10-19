// HTTP helpers for collection tests using the shared Box identity fixtures.
// Exports collection requests, typed creation and membership mutation assertions.
import { SELF } from 'cloudflare:test';
import { expect } from 'vitest';
import { OWNER, type Item } from '../../box-test-helpers';
import { authHeaders } from '../../test-helpers';
import type { BoxCollection } from './store';

export function collections(path = '', method = 'GET', body?: unknown,
  token = OWNER): Promise<Response> {
  return SELF.fetch(`https://test.local/api/box/collections${path}`, {
    method,
    headers: { ...(token === 'agent' ? authHeaders() : { Authorization: `Bearer ${token}` }),
      'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

export async function newCollection(name: string, token = OWNER): Promise<BoxCollection> {
  const response = await collections('', 'POST', { name }, token);
  expect(response.status, await response.clone().text()).toBe(201);
  return response.json() as Promise<BoxCollection>;
}

export async function membership(collectionId: string, itemId: string, method = 'PUT',
  token = OWNER): Promise<Item> {
  const response = await collections(`/${collectionId}/items/${itemId}`, method, undefined, token);
  expect(response.status, await response.clone().text()).toBe(200);
  return response.json() as Promise<Item>;
}

export async function collectionList(token = OWNER): Promise<BoxCollection[]> {
  const response = await collections('', 'GET', undefined, token);
  expect(response.status).toBe(200);
  return (await response.json() as { collections: BoxCollection[] }).collections;
}
