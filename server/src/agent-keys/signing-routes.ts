// Agent self-enrollment of message-signing keys and the boss reset surface.
// Exports agentSigningRouter (/api/agents/me/signing-keys) and bossAgentSigningRouter.
// Depends on the message-security key registry, auth middleware and boss notification.

import { Hono, type Context, type Next } from 'hono';
import type { Env } from '../types';
import { apiAuth, bossAuth, getAgentId, getAgentKeyId, getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from '../routes/boss-api-access';
import {
  agentRequiresSignature, enrollAgentSigningKey, listLiveAgentKeys, listUnresetAgentKeys, revokeAgentSigningKey, systemMetadata,
  type AgentSigningKey,
} from '../message-security';
import { dispatchDestinations } from '../delivery';
import { notifyBossAgents } from '../notify';
import { createMessageId, insertMessageWithEvent } from '../session-events';

type SigningContext = Context<{ Bindings: Env }>;
export const agentSigningRouter = new Hono<{ Bindings: Env }>();
agentSigningRouter.use('*', apiAuth);

agentSigningRouter.get('/', async c => {
  const keys = await listLiveAgentKeys(c.env, getAgentId(c));
  const current = keys.find(key => key.agent_key_id === getAgentKeyId(c)) ?? null;
  const required = await agentRequiresSignature(c.env, getAgentId(c));
  return c.json({ keys: keys.map(publicView), current_key_id: current?.key_id ?? null, required });
});

agentSigningRouter.post('/', async c => {
  const agentKeyId = getAgentKeyId(c);
  if (!agentKeyId) return c.text('this credential predates agent_keys; rotate it with `hiboss key rotate` first', 409);
  const payload = await c.req.json<Record<string, unknown>>().catch(() => ({} as Record<string, unknown>));
  const result = await enrollAgentSigningKey(c.env, {
    agentId: getAgentId(c), agentKeyId,
    publicKey: payload['public_key'], proof: payload['proof'], endorsement: payload['endorsement'],
  });
  if (!result.ok) return c.text(result.error, result.status);
  if (result.created && result.key.enrolled_via === 'first_use') {
    c.executionCtx.waitUntil(noticeFirstUse(c.env, result.key));
  }
  return c.json(publicView(result.key), result.created ? 201 : 200);
});

/** First-use enrollment is trust on first use, so the boss always hears about it. */
async function noticeFirstUse(env: Env, key: AgentSigningKey): Promise<void> {
  const body = `Message signing enabled with key ${fingerprint(key.key_id)}. `
    + 'From now on this agent\'s messages must carry this signature. If you did not expect this, reset its signing keys.';
  const inserted = await insertMessageWithEvent(env,
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal', ?) RETURNING *",
    [createMessageId(), key.agent_id, body, JSON.stringify(systemMetadata({ signing_key_id: key.key_id }))], null);
  if (!inserted) return;
  await dispatchDestinations(env, inserted);
  await notifyBossAgents(env, key.agent_id, inserted);
}

export const bossAgentSigningRouter = new Hono<{ Bindings: Env }>();
async function bossAccess(c: SigningContext, next: Next): Promise<Response | void> {
  const role = getBossRole(c);
  if (role !== 'admin' && role !== 'manager') return c.text('admin or manager required', 403);
  const ids = await getAccessibleAgentIds(c.env, getBossId(c), role);
  if (!ids.includes(c.req.param('agentId') ?? '')) return c.text('not found', 404);
  await next();
}
bossAgentSigningRouter.use('/:agentId/signing-keys', bossAuth, bossAccess);
bossAgentSigningRouter.use('/:agentId/signing-keys/*', bossAuth, bossAccess);
bossAgentSigningRouter.get('/:agentId/signing-keys', async c => c.json({
  keys: (await listUnresetAgentKeys(c.env, c.req.param('agentId')))
    .map(key => ({ ...publicView(key), credential_live: key.credential_live === 1 })),
}));
bossAgentSigningRouter.delete('/:agentId/signing-keys', c => reset(c, null));
bossAgentSigningRouter.delete('/:agentId/signing-keys/:keyId', c => reset(c, c.req.param('keyId')));

async function reset(c: SigningContext, keyId: string | null): Promise<Response> {
  const revoked = await revokeAgentSigningKey(c.env, c.req.param('agentId') ?? '', keyId, { type: 'boss', id: getBossId(c) });
  if (keyId && revoked === 0) return c.text('not found', 404);
  return c.json({ revoked });
}

function publicView(key: AgentSigningKey): Record<string, unknown> {
  return {
    key_id: key.key_id, agent_key_id: key.agent_key_id, public_key: key.public_key,
    enrolled_via: key.enrolled_via, created_at: key.created_at, fingerprint: fingerprint(key.key_id),
  };
}

function fingerprint(keyId: string): string {
  return keyId.slice(0, 16).replace(/(.{4})(?=.)/g, '$1-');
}
