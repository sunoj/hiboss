// Collection HTTP routes mounted under the authenticated Box router.
// Agents organize readable bosses’ collections; collection deletion remains boss-only.
import { Hono } from 'hono';
import type { Env } from '../../types';
import { isBossAuth } from '../../middleware/auth';
import { boxWriteScope } from '../access';
import { findItem } from '../store';
import { itemResponse } from '../types';
import { collectionName } from './validation';
import { deleteCollection, findCollection, listCollections, saveCollection, setMembership } from './store';

export const collectionRoutes = new Hono<{ Bindings: Env }>();

collectionRoutes.get('/', async c => c.json({ collections: await listCollections(c) }));

collectionRoutes.post('/', async c => {
  const name = await collectionName(c);
  const body = await c.req.json<{ boss?: unknown }>();
  if (body.boss !== undefined && typeof body.boss !== 'string') return c.text('invalid boss', 400);
  const scope = await boxWriteScope(c, body.boss?.trim() ?? null);
  return c.json(await saveCollection(c, scope.bossId, name), 201);
});

collectionRoutes.patch('/:id', async c => {
  const collection = await findCollection(c, c.req.param('id'));
  if (!collection) return c.text('not found', 404);
  return c.json(await saveCollection(c, collection.boss_id, await collectionName(c), collection.id));
});

collectionRoutes.delete('/:id', async c => {
  if (!isBossAuth(c)) return c.text('not found', 404);
  const collection = await findCollection(c, c.req.param('id'));
  if (!collection) return c.text('not found', 404);
  await deleteCollection(c, collection.id);
  return c.body(null, 204);
});

collectionRoutes.on(['PUT', 'DELETE'], '/:id/items/:item_id', async c => {
  const collection = await findCollection(c, c.req.param('id'));
  const item = await findItem(c, c.req.param('item_id'));
  if (!collection || !item || collection.boss_id !== item.boss_id) {
    return c.text('not found', 404);
  }
  await setMembership(c, collection.id, item.id, c.req.method === 'PUT');
  const updated = await findItem(c, item.id);
  return updated ? c.json(itemResponse(updated)) : c.text('not found', 404);
});
