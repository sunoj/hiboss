// Authenticated Box item routes for boss ingestion and scoped reads and edits.
// Exports boxRouter; delegates validation, storage, search and private media.
import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { Env } from '../types';
import { dualAuth, isBossAuth } from '../middleware/auth';
import { boxWriteScope, canEditItem } from './access';
import { createItem, deleteItem, findItem, replayItem, updateItem } from './store';
import { parsePatch, parseUpload } from './validation';
import { boxMedia } from './media';
import { boxList, boxLatest, boxSearch } from './search';
import { itemResponse } from './types';

const routes = new Hono<{ Bindings: Env }>();
routes.use('*', dualAuth);
routes.onError((error) => {
  if (error instanceof HTTPException) return error.getResponse();
  throw error;
});

routes.post('/items', async (c) => {
  const key = c.req.header('Idempotency-Key');
  if (key !== undefined && (!key.trim() || key.length > 256)) {
    return c.text('invalid idempotency key', 400);
  }
  const bossScope = isBossAuth(c) ? await boxWriteScope(c, null) : null;
  if (key && bossScope) {
    const replay = await replayItem(c, bossScope, key);
    if (replay !== undefined) return replay ? c.json(itemResponse(replay), 201) : c.text('not found', 404);
  }
  const upload = await parseUpload(c);
  const scope = bossScope ?? await boxWriteScope(c, upload.boss);
  if (key && !bossScope) {
    const replay = await replayItem(c, scope, key);
    if (replay !== undefined) return replay ? c.json(itemResponse(replay), 201) : c.text('not found', 404);
  }
  const row = await createItem(c, scope, upload, key);
  return row ? c.json(itemResponse(row), 201) : c.text('not found', 404);
});

routes.get('/items', boxList);
routes.get('/items/latest', boxLatest);
routes.get('/items/search', boxSearch);
routes.on(['GET', 'HEAD'], '/items/:id/media', boxMedia);
routes.get('/items/:id', async (c) => {
  const row = await findItem(c, c.req.param('id'));
  return row ? c.json(itemResponse(row)) : c.text('not found', 404);
});

routes.patch('/items/:id', async (c) => {
  const row = await findItem(c, c.req.param('id'));
  if (!row || !canEditItem(c, row)) return c.text('not found', 404);
  const updated = await updateItem(c, row, await parsePatch(c));
  return updated ? c.json(itemResponse(updated)) : c.text('not found', 404);
});

routes.delete('/items/:id', async (c) => {
  const purge = c.req.query('purge') === '1';
  const row = await findItem(c, c.req.param('id'), purge);
  if (!row || !canEditItem(c, row)) return c.text('not found', 404);
  await deleteItem(c, row, purge);
  return c.body(null, 204);
});

export const boxRouter = routes;
