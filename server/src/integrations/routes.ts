// Admin-agent routes that create integrations and issue, rotate and revoke webhook URLs.
// Exports the /api/integrations router; a token appears only in the create/add/rotate response.
// Dependencies: Hono, agent auth with the is_admin gate, and the integrations repository.
import { Hono } from 'hono';
import type { Context } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { agentAdmin } from '../middleware/agent-admin';
import { webhookPath } from './credentials';
import {
  addWebhook, createIntegration, listIntegrations, revokeWebhook, rotateWebhook, type PriorityCap,
} from './repository';

const router = new Hono<{ Bindings: Env }>({});
router.use('*', apiAuth);
router.use('*', agentAdmin);

const CAPS: PriorityCap[] = ['low', 'normal', 'high'];
const WEBHOOK_ID = /^[0-9]{17,20}$/;

function text(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= max && !/[\u0000-\u001f\u007f]/.test(trimmed) ? trimmed : null;
}

async function readInput(c: Context<{ Bindings: Env }>): Promise<{ name: string | null; cap: PriorityCap | null }> {
  const body = await c.req.json<Record<string, unknown>>().catch(() => ({} as Record<string, unknown>));
  const cap = body.priority_cap === undefined ? 'normal' : CAPS.find((value) => value === body.priority_cap) ?? null;
  return { name: text(body.name ?? body.label, 100), cap };
}

function issued(c: Context<{ Bindings: Env }>, id: string, token: string) {
  return { id, url: new URL(webhookPath(id, token), c.req.url).toString() };
}

router.post('/', async (c) => {
  const { name, cap } = await readInput(c);
  if (!name) return c.text('name is required (1-100 characters)', 400);
  if (!cap) return c.text('priority_cap must be low, normal or high', 400);
  const created = await createIntegration(c.env.DB, name, cap, getAgentId(c));
  if (!created) return c.text('agent name already exists', 409);
  const { webhook, ...integration } = created;
  return c.json({ ...integration, webhook: { ...issued(c, webhook.id, webhook.token),
    label: webhook.label, priority_cap: webhook.priority_cap } }, 201);
});

router.get('/', async (c) => c.json({ webhooks: await listIntegrations(c.env.DB) }));

router.post('/:agentId/webhooks', async (c) => {
  const { name, cap } = await readInput(c);
  if (!name) return c.text('label is required (1-100 characters)', 400);
  if (!cap) return c.text('priority_cap must be low, normal or high', 400);
  const webhook = await addWebhook(c.env.DB, c.req.param('agentId'), name, cap, getAgentId(c));
  if (!webhook) return c.text('integration not found', 404);
  return c.json({ ...issued(c, webhook.id, webhook.token), label: webhook.label,
    priority_cap: webhook.priority_cap }, 201);
});

router.post('/webhooks/:id/rotate', async (c) => {
  const id = c.req.param('id');
  const token = WEBHOOK_ID.test(id) ? await rotateWebhook(c.env.DB, id, getAgentId(c)) : null;
  return token ? c.json(issued(c, id, token)) : c.text('webhook not found', 404);
});

router.delete('/webhooks/:id', async (c) => {
  const id = c.req.param('id');
  const revoked = WEBHOOK_ID.test(id) && await revokeWebhook(c.env.DB, id, getAgentId(c));
  return revoked ? c.body(null, 204) : c.text('webhook not found', 404);
});

export default router;
