// Admin API for managing the Discord Gateway Durable Object connection.
// Exports connect/disconnect/status endpoints behind auth.
// Depends on Hono, auth middleware, and DISCORD_GATEWAY DO binding.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

type GwEnv = Env & { DISCORD_GATEWAY: DurableObjectNamespace };

const router = new Hono<{ Bindings: GwEnv }>({});
router.use('*', apiAuth);

function getStub(env: GwEnv): DurableObjectStub {
  const id = env.DISCORD_GATEWAY.idFromName('singleton');
  return env.DISCORD_GATEWAY.get(id);
}

router.post('/connect', async (c) => {
  const payload = await c.req.json<{ bot_token?: string }>().catch(() => ({ bot_token: undefined }));
  const stub = getStub(c.env);
  const resp = await stub.fetch(new Request('http://do/connect', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ bot_token: payload.bot_token }),
  }));
  return c.json(await resp.json(), resp.status as 200 | 400);
});

router.post('/disconnect', async (c) => {
  const stub = getStub(c.env);
  const resp = await stub.fetch(new Request('http://do/disconnect', { method: 'POST' }));
  return c.json(await resp.json());
});

router.get('/status', async (c) => {
  const stub = getStub(c.env);
  const resp = await stub.fetch(new Request('http://do/status'));
  return c.json(await resp.json());
});

export const discordGatewayRouter = router;
