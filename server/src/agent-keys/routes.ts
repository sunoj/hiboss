// Self-service and boss credential endpoints with scoped access and audit records.
// Exports routers; depends on Hono, auth, accessible agents and key persistence.
import { Hono, type Context, type Next } from 'hono';
import type { Env } from '../types';
import { apiAuth, bossAuth, getAgentId, getAgentKeyId, getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from '../routes/boss-api-access';
import { listKeys, mintKey, revokeKey } from './repository';
import { MAX_LABEL_LENGTH, type KeyActor } from './types';

type KeyContext = Context<{ Bindings: Env }>;
export const agentKeysRouter = new Hono<{ Bindings: Env }>();
agentKeysRouter.use('*', apiAuth);
agentKeysRouter.get('/', c => list(c, getAgentId(c), { type: 'agent', id: getAgentId(c) }));
agentKeysRouter.post('/', c => mint(c, getAgentId(c), { type: 'agent', id: getAgentId(c) }));
agentKeysRouter.delete('/:id', c => revoke(c, getAgentId(c), { type: 'agent', id: getAgentId(c) }, getAgentKeyId(c)));

export const bossAgentKeysRouter = new Hono<{ Bindings: Env }>();
async function bossKeyAccess(c: KeyContext, next: Next): Promise<Response | void> {
  const role = getBossRole(c);
  if (role !== 'admin' && role !== 'manager') return c.text('admin or manager required', 403);
  const ids = await getAccessibleAgentIds(c.env, getBossId(c), role);
  if (!ids.includes(c.req.param('agentId') ?? '')) return c.text('not found', 404);
  await next();
}
bossAgentKeysRouter.use('/:agentId/keys', bossAuth, bossKeyAccess);
bossAgentKeysRouter.use('/:agentId/keys/*', bossAuth, bossKeyAccess);
bossAgentKeysRouter.get('/:agentId/keys', c => list(c, c.req.param('agentId'), { type: 'boss', id: getBossId(c) }));
bossAgentKeysRouter.post('/:agentId/keys', c => mint(c, c.req.param('agentId'), { type: 'boss', id: getBossId(c) }));
bossAgentKeysRouter.delete('/:agentId/keys/:id', c => revoke(c, c.req.param('agentId'), { type: 'boss', id: getBossId(c) }, null));

async function list(c: KeyContext, agentId: string, actor: KeyActor): Promise<Response> {
  return c.json({ keys: await listKeys(c.env.DB, agentId, actor), current_key_id: getAgentKeyId(c) });
}

async function mint(c: KeyContext, agentId: string, actor: KeyActor): Promise<Response> {
  const payload: unknown = await c.req.json().catch(() => null);
  if (!payload || typeof payload !== 'object' || !('label' in payload) || typeof payload.label !== 'string') {
    return c.text('label is required', 400);
  }
  const label = payload.label.trim();
  if (!label || label.length > MAX_LABEL_LENGTH) return c.text('label must be 1–100 characters', 400);
  return c.json(await mintKey(c.env.DB, agentId, label, actor), 201);
}

async function revoke(c: KeyContext, agentId: string, actor: KeyActor, currentId: string | null): Promise<Response> {
  const result = await revokeKey(c.env.DB, agentId, c.req.param('id') ?? '', actor, currentId);
  if (result === 'missing') return c.text('not found', 404);
  if (result === 'last') return c.text('cannot revoke the current key when it is the last live key', 409);
  return c.json({ ok: true });
}
